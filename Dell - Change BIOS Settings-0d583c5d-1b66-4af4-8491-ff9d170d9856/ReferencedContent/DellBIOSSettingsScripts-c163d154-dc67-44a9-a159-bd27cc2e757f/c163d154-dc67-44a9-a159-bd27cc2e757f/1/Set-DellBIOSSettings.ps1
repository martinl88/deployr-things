#Requires -RunAsAdministrator

[CmdletBinding()]
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
    [string]$SettingsCsv = '',

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

try {
    Import-Module DellBIOSProvider -Force -ErrorAction Stop
}
catch {
    Write-Log -Message "ERROR: DellBIOSProvider module could not be loaded. Make sure it is installed. $_" -Type 3
    ExitWithCode -exitcode 1
}

$settingsConfig = @(
    [PSCustomObject]@{ Name = 'KeyboardIllumination'; DefaultValue = 'Bright'; FallbackPath = 'DellSmbios:\SystemConfiguration\KeyboardIllumination'; FallbackPossibleValues = @('Disabled','Dim','Bright') },
    [PSCustomObject]@{ Name = 'UsbPowerShare'; DefaultValue = 'Enabled'; FallbackPath = 'DellSmbios:\SystemConfiguration\UsbPowerShare'; FallbackPossibleValues = @('Disabled','Enabled') },
    [PSCustomObject]@{ Name = 'Absolute'; DefaultValue = 'DisableAbsolute'; FallbackPath = 'DellSmbios:\Security\Absolute'; FallbackPossibleValues = @('EnableAbsolute','DisableAbsolute','PermanentlyDisabled') },
    [PSCustomObject]@{ Name = 'PrimaryBattChargeCfg'; DefaultValue = 'PrimAcUse'; FallbackPath = 'DellSmbios:\PowerManagement\PrimaryBattChargeCfg'; FallbackPossibleValues = @('Adaptive','Standard','Express','PrimAcUse','Custom') },
    [PSCustomObject]@{ Name = 'FnLock'; DefaultValue = 'Enabled'; FallbackPath = 'DellSmbios:\POSTBehavior\FnLock'; FallbackPossibleValues = @('Disabled','Enabled') },
    [PSCustomObject]@{ Name = 'FnLockMode'; DefaultValue = 'EnableSecondary'; FallbackPath = 'DellSmbios:\POSTBehavior\FnLockMode'; FallbackPossibleValues = @('DisableStandard','EnableSecondary') },
    [PSCustomObject]@{ Name = 'WlanAutoSense'; DefaultValue = 'Enabled'; FallbackPath = 'DellSmbios:\PowerManagement\WlanAutoSense'; FallbackPossibleValues = @('Disabled','Enabled') },
    [PSCustomObject]@{ Name = 'WakeOnAc'; DefaultValue = 'Disabled'; FallbackPath = 'DellSmbios:\PowerManagement\WakeOnAc'; FallbackPossibleValues = @('Disabled','Enabled') },
    [PSCustomObject]@{ Name = 'WakeOnLan'; DefaultValue = 'LanOnly'; FallbackPath = 'DellSmbios:\PowerManagement\WakeOnLan'; FallbackPossibleValues = @('Disabled','LanOnly','LanWithPxeBoot') },
    [PSCustomObject]@{ Name = 'NumLock'; DefaultValue = 'Enabled'; FallbackPath = 'DellSmbios:\POSTBehavior\NumLock'; FallbackPossibleValues = @('Disabled','Enabled') }
)

$csvLookup = @{}
if (-not $SettingsCsv) {
    $csvSearchPaths = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'DellBiosSettings.csv'),
        (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'DellBiosSettings.csv')
    )
    $SettingsCsv = $csvSearchPaths | Where-Object { Test-Path -Path $_ } | Select-Object -First 1
}

if ($SettingsCsv -and (Test-Path -Path $SettingsCsv)) {
    Write-Log -Message "Loading DellBiosSettings.csv from $SettingsCsv" -Type 1
    $csvRows = Import-Csv -Path $SettingsCsv
    foreach ($row in $csvRows) {
        if (-not $csvLookup.ContainsKey($row.Attribute)) {
            $csvLookup[$row.Attribute] = $row
        }
    }
}
else {
    Write-Log -Message 'DellBiosSettings.csv not found; using built-in fallback paths and possible values.' -Type 2
}

$settingsToApply = foreach ($cfg in $settingsConfig) {
    $csvRow = $csvLookup[$cfg.Name]
    $path = if ($csvRow) { $csvRow.Path } else { $cfg.FallbackPath }
    $possibleValues = if ($csvRow -and $csvRow.PossibleValues) {
        $csvRow.PossibleValues -split ';' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    else {
        $cfg.FallbackPossibleValues
    }

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

    if ($possibleValues -and ($value -notin $possibleValues)) {
        Write-Log -Message "WARNING: Value '$value' for '$($cfg.Name)' is not in the known possible values ($($possibleValues -join '; ')); using default '$($cfg.DefaultValue)'." -Type 2
        $value = $cfg.DefaultValue
    }

    [PSCustomObject]@{
        Name = $cfg.Name
        Path = $path
        Value = $value
        PossibleValues = $possibleValues
    }
}

function Set-DellBiosSetting {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Value,
        [string]$Password,
        [bool]$AdminSet
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Log -Message "Setting '$Name' is not available on this system; skipping." -Type 2
        return
    }

    try {
        $current = (Get-Item -Path $Path).CurrentValue
        if ($current -eq $Value) {
            Write-Log -Message "Setting '$Name' is already '$Value'; skipping." -Type 1
            return
        }

        Write-Log -Message "Setting '$Name' to '$Value' ..." -Type 1
        if ($AdminSet) {
            Set-Item -Path $Path $Value -Password $Password
        }
        else {
            Set-Item -Path $Path $Value
        }
        Write-Log -Message "Setting '$Name' updated successfully." -Type 1
    }
    catch {
        Write-Log -Message "ERROR: Failed to set '$Name' to '$Value' - $($_.Exception.Message)" -Type 3
        throw
    }
}

function Set-DellBiosAdminPassword {
    param(
        [string]$Password
    )

    if (-not (Test-Path -Path 'DellSmbios:\Security\AdminPassword')) {
        Write-Log -Message 'AdminPassword path is not available; cannot set admin password.' -Type 2
        return
    }

    $isSet = (Get-Item -Path 'DellSmbios:\Security\IsAdminPasswordSet').CurrentValue -eq 'True'
    if ($isSet) {
        Write-Log -Message 'Admin password is already set; skipping set.' -Type 1
        return
    }

    Write-Log -Message 'Setting admin password ...' -Type 1
    try {
        Set-Item -Path 'DellSmbios:\Security\AdminPassword' $Password
        Write-Log -Message 'Admin password set successfully.' -Type 1
    }
    catch {
        Write-Log -Message "ERROR: Failed to set admin password - $($_.Exception.Message)" -Type 3
        throw
    }
}

function Clear-DellBiosAdminPassword {
    param(
        [string]$Password
    )

    if (-not (Test-Path -Path 'DellSmbios:\Security\AdminPassword')) {
        Write-Log -Message 'AdminPassword path is not available; cannot clear admin password.' -Type 2
        return
    }

    $isSet = (Get-Item -Path 'DellSmbios:\Security\IsAdminPasswordSet').CurrentValue -eq 'True'
    if (-not $isSet) {
        Write-Log -Message 'Admin password is not set; nothing to clear.' -Type 1
        return
    }

    Write-Log -Message 'Clearing admin password ...' -Type 1
    try {
        Set-Item -Path 'DellSmbios:\Security\AdminPassword' '' -Password $Password
        Write-Log -Message 'Admin password cleared successfully.' -Type 1
    }
    catch {
        Write-Log -Message "ERROR: Failed to clear admin password - $($_.Exception.Message)" -Type 3
        throw
    }
}

function Set-DellBiosSystemPassword {
    param(
        [string]$Password,
        [string]$AdminPassword,
        [bool]$AdminSet
    )

    if (-not (Test-Path -Path 'DellSmbios:\Security\SystemPassword')) {
        Write-Log -Message 'SystemPassword path is not available; cannot set system password.' -Type 2
        return
    }

    $isSet = (Get-Item -Path 'DellSmbios:\Security\IsSystemPasswordSet').CurrentValue -eq 'True'
    if ($isSet) {
        Write-Log -Message 'System password is already set; skipping set.' -Type 1
        return
    }

    Write-Log -Message 'Setting system password ...' -Type 1
    try {
        if ($AdminSet) {
            Set-Item -Path 'DellSmbios:\Security\SystemPassword' $Password -Password $AdminPassword
        }
        else {
            Set-Item -Path 'DellSmbios:\Security\SystemPassword' $Password
        }
        Write-Log -Message 'System password set successfully.' -Type 1
    }
    catch {
        Write-Log -Message "ERROR: Failed to set system password - $($_.Exception.Message)" -Type 3
        throw
    }
}

function Clear-DellBiosSystemPassword {
    param(
        [string]$Password
    )

    if (-not (Test-Path -Path 'DellSmbios:\Security\SystemPassword')) {
        Write-Log -Message 'SystemPassword path is not available; cannot clear system password.' -Type 2
        return
    }

    $isSet = (Get-Item -Path 'DellSmbios:\Security\IsSystemPasswordSet').CurrentValue -eq 'True'
    if (-not $isSet) {
        Write-Log -Message 'System password is not set; nothing to clear.' -Type 1
        return
    }

    Write-Log -Message 'Clearing system password ...' -Type 1
    try {
        Set-Item -Path 'DellSmbios:\Security\SystemPassword' '' -Password $Password
        Write-Log -Message 'System password cleared successfully.' -Type 1
    }
    catch {
        Write-Log -Message "ERROR: Failed to clear system password - $($_.Exception.Message)" -Type 3
        throw
    }
}

$adminSet = (Get-Item -Path 'DellSmbios:\Security\IsAdminPasswordSet').CurrentValue -eq 'True'
$systemSet = $false
if (Test-Path -Path 'DellSmbios:\Security\IsSystemPasswordSet') {
    $systemSet = (Get-Item -Path 'DellSmbios:\Security\IsSystemPasswordSet').CurrentValue -eq 'True'
}

if ($ClearAdminPassword -and $adminSet -and [string]::IsNullOrWhiteSpace($BiosPassword)) {
    Write-Log -Message 'ERROR: -BiosPassword is required when clearing an existing admin password.' -Type 3
    ExitWithCode -exitcode 1
}

if (-not $ClearAdminPassword -and -not $adminSet -and [string]::IsNullOrWhiteSpace($BiosPassword)) {
    Write-Log -Message 'ERROR: -BiosPassword is required to set the admin password on a system that does not have one.' -Type 3
    ExitWithCode -exitcode 1
}

if ([string]::IsNullOrWhiteSpace($BiosPassword) -and $adminSet) {
    Write-Log -Message 'ERROR: -BiosPassword is required when an admin password is already set.' -Type 3
    ExitWithCode -exitcode 1
}

if ($ClearSystemPassword -and $systemSet -and [string]::IsNullOrWhiteSpace($SystemPassword) -and [string]::IsNullOrWhiteSpace($BiosPassword)) {
    Write-Log -Message 'ERROR: -SystemPassword or -BiosPassword is required when clearing an existing system password.' -Type 3
    ExitWithCode -exitcode 1
}

if ($ClearSystemPassword -and -not $systemSet -and [string]::IsNullOrWhiteSpace($BiosPassword) -and -not $adminSet) {
    # Nothing to clear, but we still may need BiosPassword to set settings if admin is not set
    # This validation is intentionally permissive; the script will simply skip clearing.
}

if (-not $ClearSystemPassword -and -not $systemSet -and -not [string]::IsNullOrWhiteSpace($SystemPassword) -and $adminSet -and [string]::IsNullOrWhiteSpace($BiosPassword)) {
    Write-Log -Message 'ERROR: -BiosPassword is required to set the system password while an admin password is set.' -Type 3
    ExitWithCode -exitcode 1
}

# Set or clear admin password before applying settings (unless we are clearing it, in which case apply settings first)
if (-not $ClearAdminPassword -and -not $adminSet) {
    Set-DellBiosAdminPassword -Password $BiosPassword
    $adminSet = (Get-Item -Path 'DellSmbios:\Security\IsAdminPasswordSet').CurrentValue -eq 'True'
}

if (-not $ClearSystemPassword -and -not $systemSet -and -not [string]::IsNullOrWhiteSpace($SystemPassword)) {
    Set-DellBiosSystemPassword -Password $SystemPassword -AdminPassword $BiosPassword -AdminSet $adminSet
    $systemSet = (Get-Item -Path 'DellSmbios:\Security\IsSystemPasswordSet').CurrentValue -eq 'True'
}

foreach ($setting in $settingsToApply) {
    Set-DellBiosSetting -Name $setting.Name -Path $setting.Path -Value $setting.Value -Password $BiosPassword -AdminSet $adminSet
}

if ($ClearSystemPassword) {
    $clearSystemPwd = if (-not [string]::IsNullOrWhiteSpace($SystemPassword)) { $SystemPassword } else { $BiosPassword }
    if (-not [string]::IsNullOrWhiteSpace($clearSystemPwd)) {
        Clear-DellBiosSystemPassword -Password $clearSystemPwd
    }
    else {
        Write-Log -Message 'System password clear was requested but no password was provided; nothing to clear.' -Type 2
    }
}

if ($ClearAdminPassword) {
    $clearAdminPwd = if (-not [string]::IsNullOrWhiteSpace($BiosPassword)) { $BiosPassword } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($clearAdminPwd)) {
        Clear-DellBiosAdminPassword -Password $clearAdminPwd
    }
    else {
        Write-Log -Message 'Admin password clear was requested but -BiosPassword was not provided; nothing to clear.' -Type 2
    }
}

Write-Log -Message '=====================================================' -Type 1
Write-Log -Message 'Dell BIOS Settings configuration completed' -Type 1
Write-Log -Message '=====================================================' -Type 1

ExitWithCode -exitcode 0
