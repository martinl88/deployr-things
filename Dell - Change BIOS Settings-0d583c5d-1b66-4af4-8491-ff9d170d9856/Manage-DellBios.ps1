#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Reads and configures Dell BIOS enumeration settings through the native WMI provider.
.DESCRIPTION
Get reports the nine profile settings, their current values, and live possible
values. Set accepts a hashtable. ApplyDefaults applies the supplied profile,
not factory defaults. All requested settings are validated before any writes.
Use Set-DellBiosPassword.ps1 to manage the BIOS administrator password itself.
.PARAMETER Action
Get (default), Set, or ApplyDefaults.
.PARAMETER Name
Optional subset of profile settings to query or apply. Not used with Set.
.PARAMETER Settings
Hashtable of setting names and values for Action Set.
.PARAMETER CurrentPassword
Existing BIOS administrator password as a string or SecureString. Prompts when
needed. Get and WhatIf never request passwords.
.PARAMETER SkipUnsupported
For Set or ApplyDefaults, report and skip settings absent from WMI. Other
validation failures still stop the entire request before any writes.
.EXAMPLE
.\Manage-DellBios.ps1
.EXAMPLE
.\Manage-DellBios.ps1 -Action Set -Settings @{ NumLock = 'Enabled' }
.EXAMPLE
.\Manage-DellBios.ps1 -Action ApplyDefaults -WhatIf
.NOTES
https://dl.dell.com/manuals/common/dell-agentless-client-manageability.pdf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Get', 'Set', 'ApplyDefaults')]
    [string]$Action = 'Get',
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,
    [ValidateNotNull()]
    [hashtable]$Settings,
    [ValidateNotNull()]
    [object]$CurrentPassword,
    [switch]$SkipUnsupported
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$profile = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'DellBiosSettings.psd1')
if ($PSBoundParameters.ContainsKey('CurrentPassword') -and
    $CurrentPassword -isnot [string] -and $CurrentPassword -isnot [System.Security.SecureString]) {
    throw 'CurrentPassword must be a string or SecureString.'
}
if ($Action -eq 'Set') {
    if ($null -eq $Settings -or $Settings.Count -eq 0 -or $PSBoundParameters.ContainsKey('Name')) {
        throw 'Action Set requires a nonempty Settings hashtable and does not accept Name.'
    }
    $Name = @($Settings.Keys | Sort-Object)
}
else {
    if ($PSBoundParameters.ContainsKey('Settings')) { throw 'Settings requires Action Set.' }
    if (-not $PSBoundParameters.ContainsKey('Name')) { $Name = @($profile.Keys | Sort-Object) }
}
foreach ($settingName in $Name) {
    if (-not $profile.ContainsKey($settingName)) { throw "Unknown profile setting: $settingName." }
}
if ($Action -eq 'Get' -and $PSBoundParameters.ContainsKey('CurrentPassword')) {
    throw 'CurrentPassword is not needed for Action Get.'
}
$computer = Get-CimInstance -ClassName Win32_ComputerSystem
if ($computer.Manufacturer -notmatch 'Dell') { throw 'This script requires a Dell computer.' }
$namespace = 'root\dcim\sysman\biosattributes'
try {
    $attributes = @(Get-CimInstance -Namespace $namespace -ClassName EnumerationAttribute)
}
catch {
    throw 'Cannot read Dell BIOS EnumerationAttribute. Run elevated on a supported Dell BIOS.'
}

# Match provider identifiers exactly (case-insensitively), never display labels
# or guessed SMBIOS aliases. Only live WMI PossibleValue entries can be written.
$plan = @()
$validationErrors = @()
foreach ($settingName in ($Name | Select-Object -Unique)) {
    $matches = @($attributes | Where-Object { $_.AttributeName -eq $settingName })
    $row = [pscustomobject]@{
        Name = $settingName
        Supported = $matches.Count -eq 1
        CurrentValue = $null
        ProfileDefault = $profile[$settingName]
        BiosDefault = $null
        PossibleValues = [string[]]@()
        ReadOnly = $null
        RequestedValue = $null
        Changed = $false
        Status = 'Not exposed by WMI'
    }
    if ($matches.Count -gt 1) { $row.Status = 'Ambiguous WMI attribute' }
    if ($row.Supported) {
        $attribute = $matches[0]
        $row.Name = $attribute.AttributeName
        $row.CurrentValue = $attribute.CurrentValue
        $row.BiosDefault = $attribute.DefaultValue
        $row.PossibleValues = [string[]]@($attribute.PossibleValue)
        $row.ReadOnly = [bool]$attribute.ReadOnly
        $row.Status = 'Read'
    }
    if ($Action -ne 'Get') {
        $requested = $profile[$settingName]
        if ($Action -eq 'Set') { $requested = $Settings[$settingName] }
        if (-not $row.Supported) {
            if ($SkipUnsupported -and $matches.Count -eq 0) {
                $row.Status = 'Skipped: not exposed by WMI'
                Write-Warning "$settingName is not exposed by WMI and will be skipped."
            }
            else {
                $validationErrors += "$settingName : $($row.Status)."
            }
        }
        elseif ($requested -isnot [string] -or [string]::IsNullOrEmpty($requested)) {
            $validationErrors += "$settingName : value must be a nonempty string."
        }
        else {
            $validValues = @($row.PossibleValues | Where-Object { $_ -eq $requested })
            if ($validValues.Count -ne 1) {
                $validationErrors += "$settingName : unsupported value '$requested'; WMI allows: $($row.PossibleValues -join ', ')."
            }
            else {
                $row.RequestedValue = $validValues[0]
                if ($row.CurrentValue -eq $row.RequestedValue) { $row.Status = 'Already configured' }
                elseif ($row.ReadOnly) { $validationErrors += "$settingName : BIOS reports read-only." }
                else { $row.Status = 'Pending' }
            }
        }
    }
    $plan += $row
}
if ($validationErrors.Count -gt 0) {
    throw "No settings were written. $($validationErrors -join ' ')"
}
if ($Action -eq 'Get') { $plan; return }

$securityBytes = [byte[]]@()
$plain = $null
$promptedPassword = $null
$arguments = $null
$ready = $false
$securityType = [uint32]0
try {
    foreach ($row in $plan) {
        if ($row.Status -eq 'Already configured' -or $row.Status -eq 'Skipped: not exposed by WMI') { $row; continue }
        $operation = "Set $($row.Name) from '$($row.CurrentValue)' to '$($row.RequestedValue)'"
        if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, $operation)) {
            $row.Status = 'Not applied'
            $row
            continue
        }
        if (-not $ready) {
            $interfaces = @(Get-CimInstance -Namespace $namespace -ClassName BIOSAttributeInterface |
                Where-Object { $_.Active })
            if ($interfaces.Count -ne 1) { throw 'Expected one active BIOSAttributeInterface. No settings were written.' }
            $passwords = @(Get-CimInstance -Namespace 'root\dcim\sysman\wmisecurity' -ClassName PasswordObject |
                Where-Object { $_.NameId -eq 'Admin' })
            if ($passwords.Count -ne 1 -or $passwords[0].IsPasswordSet -notin @(0, 1)) {
                throw 'Cannot determine Admin password state. No settings were written.'
            }
            if ($passwords[0].IsPasswordSet -eq 1) {
                if ($null -eq $CurrentPassword) {
                    $promptedPassword = Read-Host 'Current BIOS administrator password' -AsSecureString
                    $CurrentPassword = $promptedPassword
                }
                if ($CurrentPassword.Length -eq 0) { throw 'CurrentPassword cannot be empty when the Admin password is set.' }
                if ($CurrentPassword -is [string]) { $plain = $CurrentPassword }
                else {
                    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($CurrentPassword)
                    try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
                    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
                }
                $securityBytes = [Text.Encoding]::UTF8.GetBytes($plain)
                $plain = $null
                $securityType = [uint32]1
            }
            elseif ($null -ne $CurrentPassword -and $CurrentPassword.Length -gt 0) {
                throw 'The BIOS reports no Admin password. Omit CurrentPassword.'
            }
            $ready = $true
        }
        $arguments = @{
            SecType = $securityType
            SecHndCount = [uint32]$securityBytes.Length
            SecHandle = $securityBytes
            AttributeName = [string]$row.Name
            AttributeValue = [string]$row.RequestedValue
        }
        try {
            $result = Invoke-CimMethod -InputObject $interfaces[0] -MethodName SetAttribute -Arguments $arguments
        }
        catch {
            throw "WMI call failed for $($row.Name); its state is unknown. Earlier changes are not rolled back. Query settings before retrying."
        }
        finally { $arguments.Clear() }
        if ($null -eq $result -or $null -eq $result.PSObject.Properties['Status'] -or $null -eq $result.Status) {
            throw "No Status returned for $($row.Name); its state is unknown. Earlier changes are not rolled back."
        }
        $status = [int]$result.Status
        if ($status -ne 0) {
            $reasons = @{ 1 = 'Failed'; 2 = 'Invalid parameter'; 3 = 'Access denied'; 4 = 'Not supported'; 5 = 'Memory error'; 6 = 'Protocol error' }
            $reason = $reasons[$status]
            if ($null -eq $reason) { $reason = 'Unknown status' }
            throw "$($row.Name): $reason (Status $status). Stopped; earlier changes are not rolled back."
        }
        $row.Changed = $true
        $row.Status = 'Provider reported success'
        $row
    }
}
finally {
    if ($null -ne $arguments) { $arguments.Clear() }
    if ($securityBytes.Length -gt 0) { [Array]::Clear($securityBytes, 0, $securityBytes.Length) }
    $plain = $null
    if ($null -ne $promptedPassword) { $promptedPassword.Dispose() }
}
