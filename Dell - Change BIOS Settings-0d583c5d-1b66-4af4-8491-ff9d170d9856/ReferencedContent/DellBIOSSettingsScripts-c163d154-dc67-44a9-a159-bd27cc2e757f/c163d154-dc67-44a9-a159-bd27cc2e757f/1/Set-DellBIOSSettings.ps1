#Requires -RunAsAdministrator

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'DeployR task-sequence variables and Dell WMI methods require plaintext strings.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Messages must be visible in the task-sequence host as well as the CMTrace log.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LogFile', Justification = 'Write-Log consumes this script-scoped parameter.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingEmptyCatchBlock', '', Justification = 'Missing optional DeployR and TSEnv providers are expected outside a task sequence.')]
param(
    [Parameter(Mandatory = $false)]
    [string]$BiosPassword = '',

    [Parameter(Mandatory = $false)]
    [switch]$ClearAdminPassword,

    [Parameter(Mandatory = $false)]
    [string]$SystemPassword = '',

    [Parameter(Mandatory = $false)]
    [switch]$ClearSystemPassword,

    [Parameter(Mandatory = $false)]
    [switch]$FailOnNonDell,

    [Parameter(Mandatory = $false)]
    [string]$LogFile = 'C:\windows\Temp\DellBIOSSettings.log'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1, 2, 3)]
        [int]$Type = 1,

        [Parameter(Mandatory = $false)]
        [string]$Component = 'DellBIOSSettings'
    )

    $Time = Get-Date -Format 'HH:mm:ss.ffffff'
    $Date = Get-Date -Format 'MM-dd-yyyy'
    $LogFileFolderPath = Split-Path -Path $LogFile -Parent

    if ($LogFileFolderPath -and !(Test-Path -Path $LogFileFolderPath)) {
        New-Item -ItemType Directory -Path $LogFileFolderPath -Force | Out-Null
    }

    $LogMessage = "<![LOG[$Message]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    Write-Host $Message
}

function ExitWithCode {
    param (
        [int]$exitcode
    )

    if ($Host.Name -ne 'ConsoleHost') {
        $host.SetShouldExit($exitcode)
    }
    exit $exitcode
}

function Get-DellProviderStatus {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Result
    )

    if ($null -eq $Result.PSObject.Properties['Status'] -or $null -eq $Result.Status) {
        throw 'The Dell WMI provider did not return a status.'
    }

    $status = [int]$Result.Status
    if ($status -ne 0) {
        $reasons = @{ 1 = 'Failed'; 2 = 'Invalid parameter'; 3 = 'Access denied'; 4 = 'Not supported'; 5 = 'Memory error'; 6 = 'Protocol error' }
        $reason = $reasons[$status]
        if (-not $reason) {
            $reason = 'Unknown status'
        }
        throw "$reason (status $status)."
    }
}

function ConvertTo-PasswordByteArray {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Password
    )

    [Text.Encoding]::UTF8.GetBytes($Password)
}

function Invoke-DellPasswordChange {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Admin', 'System')]
        [string]$NameId,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$OldPassword,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$NewPassword,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$AuthorizationPassword
    )

    $securityBytes = [byte[]]@()
    $arguments = $null
    try {
        if (-not [string]::IsNullOrEmpty($AuthorizationPassword)) {
            $securityBytes = ConvertTo-PasswordByteArray -Password $AuthorizationPassword
        }
        $arguments = @{
            SecType = if ($securityBytes.Length -gt 0) { [uint32]1 } else { [uint32]0 }
            SecHndCount = [uint32]$securityBytes.Length
            SecHandle = $securityBytes
            NameId = $NameId
            OldPassword = $OldPassword
            NewPassword = $NewPassword
        }
        $result = Invoke-CimMethod -InputObject $script:SecurityInterface -MethodName SetNewPassword -Arguments $arguments
        Get-DellProviderStatus -Result $result
    }
    finally {
        if ($null -ne $arguments) {
            $arguments.Clear()
        }
        if ($securityBytes.Length -gt 0) {
            [Array]::Clear($securityBytes, 0, $securityBytes.Length)
        }
    }
}

function Get-DellPasswordState {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Admin', 'System')]
        [string]$NameId
    )

    $passwordObjects = @(Get-CimInstance -Namespace $script:SecurityNamespace -ClassName PasswordObject | Where-Object { $_.NameId -eq $NameId })
    if ($NameId -eq 'System' -and $passwordObjects.Count -eq 0) {
        return $false
    }
    if ($passwordObjects.Count -ne 1 -or $passwordObjects[0].IsPasswordSet -notin @(0, 1)) {
        throw "Cannot determine the Dell BIOS $NameId password state."
    }
    $passwordObjects[0].IsPasswordSet -eq 1
}

function Invoke-DellBiosSetting {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Setting,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Password,

        [Parameter(Mandatory = $true)]
        [bool]$AdminSet
    )

    if (-not $Setting.Supported) {
        Write-Log -Message "Setting '$($Setting.Name)' is not available on this system; skipping." -Type 2
        return
    }

    if ($Setting.CurrentValue -eq $Setting.Value) {
        Write-Log -Message "Setting '$($Setting.Name)' is already '$($Setting.Value)'; skipping." -Type 1
        return
    }

    $securityBytes = [byte[]]@()
    $arguments = $null
    try {
        if ($AdminSet) {
            $securityBytes = ConvertTo-PasswordByteArray -Password $Password
        }
        Write-Log -Message "Setting '$($Setting.Name)' to '$($Setting.Value)' ..." -Type 1
        $arguments = @{
            SecType = if ($AdminSet) { [uint32]1 } else { [uint32]0 }
            SecHndCount = [uint32]$securityBytes.Length
            SecHandle = $securityBytes
            AttributeName = [string]$Setting.Name
            AttributeValue = [string]$Setting.Value
        }
        $result = Invoke-CimMethod -InputObject $script:AttributeInterface -MethodName SetAttribute -Arguments $arguments
        Get-DellProviderStatus -Result $result
        Write-Log -Message "Setting '$($Setting.Name)' updated successfully." -Type 1
    }
    catch {
        Write-Log -Message "ERROR: Failed to set '$($Setting.Name)' to '$($Setting.Value)' - $($_.Exception.Message)" -Type 3
        throw
    }
    finally {
        if ($null -ne $arguments) {
            $arguments.Clear()
        }
        if ($securityBytes.Length -gt 0) {
            [Array]::Clear($securityBytes, 0, $securityBytes.Length)
        }
    }
}

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    # Module is not available outside of the task sequence environment
}

if (Get-Module -Name 'DeployR.Utility') {
    if (${TSEnv:BiosPassword}) {
        $BiosPassword = ${TSEnv:BiosPassword}
    }
    if (${TSEnv:ClearAdminPassword}) {
        $ClearAdminPassword = [bool]::Parse(${TSEnv:ClearAdminPassword})
    }
    if (${TSEnv:SystemPassword}) {
        $SystemPassword = ${TSEnv:SystemPassword}
    }
    if (${TSEnv:ClearSystemPassword}) {
        $ClearSystemPassword = [bool]::Parse(${TSEnv:ClearSystemPassword})
    }
}

Write-Log -Message '=====================================================' -Type 1
Write-Log -Message 'Starting Dell BIOS Settings configuration' -Type 1
Write-Log -Message "Clear admin password: $ClearAdminPassword" -Type 1
Write-Log -Message "Clear system password: $ClearSystemPassword" -Type 1
Write-Log -Message '=====================================================' -Type 1

$manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).Manufacturer
Write-Log -Message "Manufacturer: $manufacturer" -Type 1

if ($manufacturer -notlike '*Dell*') {
    $msg = "This system is not a Dell (manufacturer: $manufacturer)."
    if ($FailOnNonDell) {
        Write-Log -Message "$msg Stopping because -FailOnNonDell was specified." -Type 3
        ExitWithCode -exitcode 1
    }
    Write-Log -Message "$msg Skipping." -Type 2
    ExitWithCode -exitcode 0
}

$script:AttributeNamespace = 'root\dcim\sysman\biosattributes'
$script:SecurityNamespace = 'root\dcim\sysman\wmisecurity'
try {
    $attributes = @(Get-CimInstance -Namespace $script:AttributeNamespace -ClassName EnumerationAttribute)
    $attributeInterfaces = @(Get-CimInstance -Namespace $script:AttributeNamespace -ClassName BIOSAttributeInterface | Where-Object { $_.Active })
    $securityInterfaces = @(Get-CimInstance -Namespace $script:SecurityNamespace -ClassName SecurityInterface)
    if ($attributeInterfaces.Count -ne 1) {
        throw 'Expected one active BIOSAttributeInterface.'
    }
    if ($securityInterfaces.Count -ne 1) {
        throw 'Expected one active SecurityInterface.'
    }
    $script:AttributeInterface = $attributeInterfaces[0]
    $script:SecurityInterface = $securityInterfaces[0]
}
catch {
    Write-Log -Message "ERROR: Dell BIOS WMI provider could not be initialized. Run elevated on a supported Dell BIOS. $($_.Exception.Message)" -Type 3
    ExitWithCode -exitcode 1
}

$settingsConfig = @(
    [PSCustomObject]@{ Name = 'KeyboardIllumination'; DefaultValue = 'Bright' },
    [PSCustomObject]@{ Name = 'UsbPowerShare'; DefaultValue = 'Enabled' },
    [PSCustomObject]@{ Name = 'PrimaryBattChargeCfg'; DefaultValue = 'PrimAcUse' },
    [PSCustomObject]@{ Name = 'FnLock'; DefaultValue = 'Enabled' },
    [PSCustomObject]@{ Name = 'FnLockMode'; DefaultValue = 'EnableSecondary' },
    [PSCustomObject]@{ Name = 'WlanAutoSense'; DefaultValue = 'Enabled' },
    [PSCustomObject]@{ Name = 'WakeOnAc'; DefaultValue = 'Disabled' },
    [PSCustomObject]@{ Name = 'WakeOnLan'; DefaultValue = 'LanOnly' },
    [PSCustomObject]@{ Name = 'NumLock'; DefaultValue = 'Enabled' }
)

$settingsToApply = foreach ($cfg in $settingsConfig) {
    $value = $cfg.DefaultValue
    try {
        $tsItem = Get-Item -Path "TSEnv:\$($cfg.Name)" -ErrorAction SilentlyContinue
        if ($tsItem -and -not [string]::IsNullOrWhiteSpace($tsItem.Value)) {
            $value = $tsItem.Value
        }
    }
    catch {
        # TSEnv variable not present
    }

    $attributeMatches = @($attributes | Where-Object { $_.AttributeName -eq $cfg.Name })
    if ($attributeMatches.Count -eq 0) {
        [PSCustomObject]@{ Name = $cfg.Name; Value = $value; CurrentValue = $null; Supported = $false }
        continue
    }
    if ($attributeMatches.Count -ne 1) {
        Write-Log -Message "ERROR: Dell WMI returned multiple attributes named '$($cfg.Name)'." -Type 3
        ExitWithCode -exitcode 1
    }

    $attribute = $attributeMatches[0]
    $possibleValues = [string[]]@($attribute.PossibleValue)
    if ($value -notin $possibleValues) {
        if ($cfg.DefaultValue -notin $possibleValues) {
            Write-Log -Message "ERROR: Value '$value' and default '$($cfg.DefaultValue)' for '$($cfg.Name)' are not supported by this BIOS. Allowed values: $($possibleValues -join '; ')." -Type 3
            ExitWithCode -exitcode 1
        }
        Write-Log -Message "WARNING: Value '$value' for '$($cfg.Name)' is not supported by this BIOS; using default '$($cfg.DefaultValue)'." -Type 2
        $value = $cfg.DefaultValue
    }
    if ([bool]$attribute.ReadOnly -and $attribute.CurrentValue -ne $value) {
        Write-Log -Message "ERROR: Setting '$($cfg.Name)' is read-only on this BIOS." -Type 3
        ExitWithCode -exitcode 1
    }

    [PSCustomObject]@{
        Name = [string]$attribute.AttributeName
        Value = [string]$value
        CurrentValue = [string]$attribute.CurrentValue
        Supported = $true
    }
}

try {
    $adminSet = Get-DellPasswordState -NameId Admin
    $systemPasswordSupported = @(Get-CimInstance -Namespace $script:SecurityNamespace -ClassName PasswordObject | Where-Object { $_.NameId -eq 'System' }).Count -eq 1
    $systemSet = Get-DellPasswordState -NameId System
    if (-not $systemPasswordSupported -and (-not [string]::IsNullOrWhiteSpace($SystemPassword) -or $ClearSystemPassword)) {
        Write-Log -Message 'System password is not available on this system; skipping.' -Type 2
        $SystemPassword = ''
        $ClearSystemPassword = $false
    }

    if ($ClearAdminPassword -and $adminSet -and [string]::IsNullOrWhiteSpace($BiosPassword)) {
        throw '-BiosPassword is required when clearing an existing admin password.'
    }
    if ([string]::IsNullOrWhiteSpace($BiosPassword) -and $adminSet) {
        throw '-BiosPassword is required when an admin password is already set.'
    }
    if ($ClearSystemPassword -and $systemSet -and [string]::IsNullOrWhiteSpace($SystemPassword) -and [string]::IsNullOrWhiteSpace($BiosPassword)) {
        throw '-SystemPassword or -BiosPassword is required when clearing an existing system password.'
    }
    if ($ClearSystemPassword -and -not $systemSet -and [string]::IsNullOrWhiteSpace($BiosPassword) -and -not $adminSet) {
        # Nothing to clear, but we still may need BiosPassword to set settings if admin is not set
        # This validation is intentionally permissive; the script will simply skip clearing.
    }
    if (-not $ClearSystemPassword -and -not $systemSet -and -not [string]::IsNullOrWhiteSpace($SystemPassword) -and $adminSet -and [string]::IsNullOrWhiteSpace($BiosPassword)) {
        throw '-BiosPassword is required to set the system password while an admin password is set.'
    }

    # Set or clear admin password before applying settings (unless we are clearing it, in which case apply settings first)
    if (-not $ClearAdminPassword -and -not $adminSet -and -not [string]::IsNullOrWhiteSpace($BiosPassword)) {
        Write-Log -Message 'Setting admin password ...' -Type 1
        Invoke-DellPasswordChange -NameId Admin -OldPassword '' -NewPassword $BiosPassword -AuthorizationPassword ''
        $adminSet = Get-DellPasswordState -NameId Admin
        if (-not $adminSet) {
            throw 'Dell WMI reported success, but the admin password is not set.'
        }
        Write-Log -Message 'Admin password set successfully.' -Type 1
    }

    if (-not $ClearSystemPassword -and -not $systemSet -and -not [string]::IsNullOrWhiteSpace($SystemPassword)) {
        Write-Log -Message 'Setting system password ...' -Type 1
        $authorizationPassword = if ($adminSet) { $BiosPassword } else { '' }
        Invoke-DellPasswordChange -NameId System -OldPassword '' -NewPassword $SystemPassword -AuthorizationPassword $authorizationPassword
        $systemSet = Get-DellPasswordState -NameId System
        if (-not $systemSet) {
            throw 'Dell WMI reported success, but the system password is not set.'
        }
        Write-Log -Message 'System password set successfully.' -Type 1
    }

    foreach ($setting in $settingsToApply) {
        Invoke-DellBiosSetting -Setting $setting -Password $BiosPassword -AdminSet $adminSet
    }

    if ($ClearSystemPassword -and $systemSet) {
        Write-Log -Message 'Clearing system password ...' -Type 1
        $clearSystemPwd = if (-not [string]::IsNullOrWhiteSpace($SystemPassword)) { $SystemPassword } else { $BiosPassword }
        $authorizationPassword = if ($adminSet -and [string]::IsNullOrWhiteSpace($SystemPassword)) { $BiosPassword } else { $clearSystemPwd }
        Invoke-DellPasswordChange -NameId System -OldPassword $clearSystemPwd -NewPassword '' -AuthorizationPassword $authorizationPassword
        if (Get-DellPasswordState -NameId System) {
            throw 'Dell WMI reported success, but the system password is still set.'
        }
        Write-Log -Message 'System password cleared successfully.' -Type 1
    }
    elseif ($ClearSystemPassword) {
        Write-Log -Message 'System password is not set; nothing to clear.' -Type 1
    }

    if ($ClearAdminPassword -and $adminSet) {
        Write-Log -Message 'Clearing admin password ...' -Type 1
        Invoke-DellPasswordChange -NameId Admin -OldPassword $BiosPassword -NewPassword '' -AuthorizationPassword $BiosPassword
        if (Get-DellPasswordState -NameId Admin) {
            throw 'Dell WMI reported success, but the admin password is still set.'
        }
        Write-Log -Message 'Admin password cleared successfully.' -Type 1
    }
    elseif ($ClearAdminPassword) {
        Write-Log -Message 'Admin password is not set; nothing to clear.' -Type 1
    }
}
catch {
    Write-Log -Message "ERROR: Dell BIOS configuration failed - $($_.Exception.Message)" -Type 3
    ExitWithCode -exitcode 1
}

Write-Log -Message '=====================================================' -Type 1
Write-Log -Message 'Dell BIOS Settings configuration completed' -Type 1
Write-Log -Message '=====================================================' -Type 1

ExitWithCode -exitcode 0
