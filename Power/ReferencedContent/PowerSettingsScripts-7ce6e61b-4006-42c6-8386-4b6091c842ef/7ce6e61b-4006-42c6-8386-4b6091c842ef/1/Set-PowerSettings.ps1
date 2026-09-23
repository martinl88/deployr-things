#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$DisplayTimeoutAc = '',
    [string]$DisplayTimeoutDc = '',
    [string]$SleepTimeoutAc = '',
    [string]$SleepTimeoutDc = '',
    [string]$HibernateTimeoutAc = '',
    [string]$HibernateTimeoutDc = '',
    [ValidateSet('NoChange', 'DoNothing', 'Sleep', 'Hibernate', 'ShutDown')]
    [string]$LidActionAc = 'NoChange',
    [ValidateSet('NoChange', 'DoNothing', 'Sleep', 'Hibernate', 'ShutDown')]
    [string]$LidActionDc = 'NoChange',
    [ValidateSet('NoChange', 'DoNothing', 'Sleep', 'Hibernate', 'ShutDown')]
    [string]$PowerButtonActionAc = 'NoChange',
    [ValidateSet('NoChange', 'DoNothing', 'Sleep', 'Hibernate', 'ShutDown')]
    [string]$PowerButtonActionDc = 'NoChange',
    [ValidateSet('NoChange', 'DoNothing', 'Sleep', 'Hibernate', 'ShutDown')]
    [string]$SleepButtonActionAc = 'NoChange',
    [ValidateSet('NoChange', 'DoNothing', 'Sleep', 'Hibernate', 'ShutDown')]
    [string]$SleepButtonActionDc = 'NoChange',
    [ValidateSet('NoChange', 'Enabled', 'Disabled')]
    [string]$Hibernation = 'NoChange',
    [ValidateSet('NoChange', 'Enabled', 'Disabled')]
    [string]$FastStartup = 'NoChange',
    [string]$LogFile = 'C:\_2P\Logs\PowerSettings.log',
    [string]$PowerCfgPath = "$env:SystemRoot\System32\powercfg.exe"
)

$ErrorActionPreference = 'Stop'
$script:PowerSettingsLogFile = $LogFile

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet(1, 2, 3)]
        [int]$Type = 1
    )

    $time = Get-Date -Format 'HH:mm:ss.ffffff'
    $date = Get-Date -Format 'MM-dd-yyyy'
    $folder = Split-Path -Path $script:PowerSettingsLogFile -Parent
    if ($folder -and -not (Test-Path -Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $logMessage = "<![LOG[$Message]LOG]!><time=`"$time`" date=`"$date`" component=`"PowerSettings`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $logMessage | Out-File -Append -Encoding UTF8 -FilePath $script:PowerSettingsLogFile
    Write-Output $Message
}

function Exit-WithCode {
    param([int]$ExitCode)

    if ($Host.Name -ne 'ConsoleHost') {
        $Host.SetShouldExit($ExitCode)
    }
    exit $ExitCode
}

function Get-TaskSequenceValue {
    param([string]$Name)

    try {
        $item = Get-Item -Path "TSEnv:\$Name" -ErrorAction SilentlyContinue
        if ($null -ne $item -and $null -ne $item.Value) {
            return [string]$item.Value
        }
    }
    catch {
        return $null
    }

    return $null
}

function Invoke-PowerCfg {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Write-Log -Message "Running powercfg $($Arguments -join ' ')"
    $output = & $PowerCfgPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($output) {
        $output | ForEach-Object { Write-Log -Message ([string]$_) }
    }
    if ($exitCode -ne 0) {
        throw "powercfg exited with code $exitCode while running: $($Arguments -join ' ')"
    }
}

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Verbose "DeployR.Utility could not be imported: $($_.Exception.Message)"
}

$optionNames = @(
    'DisplayTimeoutAc',
    'DisplayTimeoutDc',
    'SleepTimeoutAc',
    'SleepTimeoutDc',
    'HibernateTimeoutAc',
    'HibernateTimeoutDc',
    'LidActionAc',
    'LidActionDc',
    'PowerButtonActionAc',
    'PowerButtonActionDc',
    'SleepButtonActionAc',
    'SleepButtonActionDc',
    'Hibernation',
    'FastStartup'
)

if (Get-Module -Name 'DeployR.Utility') {
    foreach ($optionName in $optionNames) {
        $value = Get-TaskSequenceValue -Name $optionName
        if ($null -ne $value) {
            Set-Variable -Name $optionName -Value $value
        }
    }
}

$timeoutSettings = @(
    [PSCustomObject]@{ Name = 'Display timeout (plugged in)'; Value = $DisplayTimeoutAc; Alias = 'monitor-timeout-ac' },
    [PSCustomObject]@{ Name = 'Display timeout (battery)'; Value = $DisplayTimeoutDc; Alias = 'monitor-timeout-dc' },
    [PSCustomObject]@{ Name = 'Sleep timeout (plugged in)'; Value = $SleepTimeoutAc; Alias = 'standby-timeout-ac' },
    [PSCustomObject]@{ Name = 'Sleep timeout (battery)'; Value = $SleepTimeoutDc; Alias = 'standby-timeout-dc' },
    [PSCustomObject]@{ Name = 'Hibernate timeout (plugged in)'; Value = $HibernateTimeoutAc; Alias = 'hibernate-timeout-ac' },
    [PSCustomObject]@{ Name = 'Hibernate timeout (battery)'; Value = $HibernateTimeoutDc; Alias = 'hibernate-timeout-dc' }
)

$actionSettings = @(
    [PSCustomObject]@{ Name = 'Lid close action (plugged in)'; Value = $LidActionAc; Mode = 'Ac'; Setting = 'LIDACTION' },
    [PSCustomObject]@{ Name = 'Lid close action (battery)'; Value = $LidActionDc; Mode = 'Dc'; Setting = 'LIDACTION' },
    [PSCustomObject]@{ Name = 'Power button action (plugged in)'; Value = $PowerButtonActionAc; Mode = 'Ac'; Setting = 'PBUTTONACTION' },
    [PSCustomObject]@{ Name = 'Power button action (battery)'; Value = $PowerButtonActionDc; Mode = 'Dc'; Setting = 'PBUTTONACTION' },
    [PSCustomObject]@{ Name = 'Sleep button action (plugged in)'; Value = $SleepButtonActionAc; Mode = 'Ac'; Setting = 'SBUTTONACTION' },
    [PSCustomObject]@{ Name = 'Sleep button action (battery)'; Value = $SleepButtonActionDc; Mode = 'Dc'; Setting = 'SBUTTONACTION' }
)

$actionIndexes = @{
    DoNothing = 0
    Sleep = 1
    Hibernate = 2
    ShutDown = 3
}

try {
    Write-Log -Message '====================================================='
    Write-Log -Message 'Starting Windows power settings configuration'
    Write-Log -Message '====================================================='

    if (-not (Test-Path -Path $PowerCfgPath -PathType Leaf)) {
        throw "powercfg.exe was not found at '$PowerCfgPath'."
    }

    foreach ($setting in $timeoutSettings) {
        if ([string]::IsNullOrWhiteSpace($setting.Value)) {
            continue
        }
        if ($setting.Value -notmatch '^\d+$') {
            throw "$($setting.Name) must be blank or a non-negative whole number of minutes. Received '$($setting.Value)'."
        }
    }

    foreach ($setting in $actionSettings) {
        if ($setting.Value -notin @('NoChange', 'DoNothing', 'Sleep', 'Hibernate', 'ShutDown')) {
            throw "$($setting.Name) has an unsupported value '$($setting.Value)'."
        }
    }

    if ($Hibernation -notin @('NoChange', 'Enabled', 'Disabled')) {
        throw "Hibernation has an unsupported value '$Hibernation'."
    }
    if ($FastStartup -notin @('NoChange', 'Enabled', 'Disabled')) {
        throw "Fast startup has an unsupported value '$FastStartup'."
    }

    $hibernateRequested = -not [string]::IsNullOrWhiteSpace($HibernateTimeoutAc) -or
        -not [string]::IsNullOrWhiteSpace($HibernateTimeoutDc) -or
        ($actionSettings.Value -contains 'Hibernate')
    if ($Hibernation -eq 'Disabled' -and ($hibernateRequested -or $FastStartup -eq 'Enabled')) {
        throw 'Hibernation cannot be disabled while a hibernate timeout, Hibernate action, or Fast startup is also requested.'
    }

    if ($Hibernation -ne 'NoChange') {
        Invoke-PowerCfg -Arguments @('/hibernate', $(if ($Hibernation -eq 'Enabled') { 'on' } else { 'off' }))
        Write-Log -Message "System hibernation changed to: $Hibernation"
    }
    elseif ($FastStartup -eq 'Enabled') {
        Invoke-PowerCfg -Arguments @('/hibernate', 'on')
        Write-Log -Message 'System hibernation enabled as a prerequisite for Fast startup'
    }

    if ($FastStartup -ne 'NoChange') {
        $fastStartupValue = if ($FastStartup -eq 'Enabled') { 1 } else { 0 }
        $powerRegistryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
        New-ItemProperty -Path $powerRegistryPath -Name 'HiberbootEnabled' -Value $fastStartupValue -PropertyType DWord -Force | Out-Null
        $appliedFastStartupValue = (Get-ItemProperty -Path $powerRegistryPath -Name 'HiberbootEnabled').HiberbootEnabled
        if ($appliedFastStartupValue -ne $fastStartupValue) {
            throw "Fast startup registry value verification failed. Expected $fastStartupValue, received $appliedFastStartupValue."
        }
        Write-Log -Message "Fast startup changed to: $FastStartup"
    }

    Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_BALANCED')
    Write-Log -Message 'Balanced power plan activated'

    foreach ($setting in $timeoutSettings) {
        if ([string]::IsNullOrWhiteSpace($setting.Value)) {
            Write-Log -Message "$($setting.Name): unchanged"
            continue
        }
        Invoke-PowerCfg -Arguments @('/change', $setting.Alias, $setting.Value)
        Write-Log -Message "$($setting.Name) changed to: $($setting.Value) minutes"
    }

    foreach ($setting in $actionSettings) {
        if ($setting.Value -eq 'NoChange') {
            Write-Log -Message "$($setting.Name): unchanged"
            continue
        }
        $command = if ($setting.Mode -eq 'Ac') { '/setacvalueindex' } else { '/setdcvalueindex' }
        Invoke-PowerCfg -Arguments @($command, 'SCHEME_BALANCED', 'SUB_BUTTONS', $setting.Setting, [string]$actionIndexes[$setting.Value])
        Write-Log -Message "$($setting.Name) changed to: $($setting.Value)"
    }

    Write-Log -Message '====================================================='
    Write-Log -Message 'Windows power settings configuration completed'
    Write-Log -Message '====================================================='
    Exit-WithCode -ExitCode 0
}
catch {
    Write-Log -Message "ERROR: $($_.Exception.Message)" -Type 3
    Exit-WithCode -ExitCode 1
}
