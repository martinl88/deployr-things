#Requires -RunAsAdministrator

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'DeployR task-sequence variables are strings and ODBC requires the PWD attribute as plain text.')]
[CmdletBinding()]
param(
    [string]$DsnName = '',
    [string]$Description = '',
    [string]$Driver = '',
    [string]$DriverOther = '',
    [string]$Server = '',
    [string]$Database = '',
    [ValidateSet('No', 'Yes')]
    [string]$TrustedConnection = 'No',
    [ValidateSet('Both', 'Platform64', 'Platform32')]
    [string]$Platform = 'Both',
    [string]$Username = '',
    [string]$Password = '',
    [string]$AdditionalAttributes = '',
    [string]$LogFile = 'C:\_2P\Logs\ODBCDsn.log'
)

$ErrorActionPreference = 'Stop'
$script:OdbcDsnLogFile = $LogFile

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Verbose "DeployR.Utility is not available outside of the task sequence environment."
}

if (Get-Module -Name 'DeployR.Utility') {
    $tsVariableNames = @('DsnName', 'Description', 'Driver', 'DriverOther', 'Server', 'Database', 'Username', 'Password', 'TrustedConnection', 'Platform', 'AdditionalAttributes')
    foreach ($varName in $tsVariableNames) {
        $tsItem = Get-Item -Path "TSEnv:\$varName" -ErrorAction SilentlyContinue
        if ($null -ne $tsItem -and -not [string]::IsNullOrWhiteSpace($tsItem.Value)) {
            Set-Variable -Name $varName -Value ([string]$tsItem.Value)
        }
    }
}

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
    $folder = Split-Path -Path $script:OdbcDsnLogFile -Parent
    if ($folder -and -not (Test-Path -Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $logMessage = "<![LOG[$Message]LOG]!><time=`"$time`" date=`"$date`" component=`"ODBCDsn`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $logMessage | Out-File -Append -Encoding UTF8 -FilePath $script:OdbcDsnLogFile
    Write-Output $Message
}

function Exit-WithCode {
    param([int]$ExitCode)

    if ($Host.Name -ne 'ConsoleHost') {
        $Host.SetShouldExit($ExitCode)
    }
    exit $ExitCode
}

function Open-OdbcRegistryKey {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Win32.RegistryView]$View,
        [Parameter(Mandatory = $true)]
        [string]$SubKeyPath,
        [switch]$Writable
    )

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $View)
    try {
        if ($Writable) {
            $key = $baseKey.OpenSubKey($SubKeyPath, $true)
            if ($null -eq $key) {
                $key = $baseKey.CreateSubKey($SubKeyPath, $true)
            }
            return $key
        }
        return $baseKey.OpenSubKey($SubKeyPath, $false)
    }
    finally {
        $baseKey.Dispose()
    }
}

function Test-OdbcDriverInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Win32.RegistryView]$View,
        [Parameter(Mandatory = $true)]
        [string]$DriverName
    )

    $key = Open-OdbcRegistryKey -View $View -SubKeyPath "SOFTWARE\ODBC\ODBCINST.INI\$DriverName"
    try {
        return ($null -ne $key)
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($DsnName)) {
        throw "DsnName is required."
    }
    if ([string]::IsNullOrWhiteSpace($Driver)) {
        throw "Driver is required."
    }

    Write-Log "Starting ODBC system DSN creation. DSN: '$DsnName'"

    $resolvedDriver = $Driver
    if ($Driver -eq 'Other') {
        $resolvedDriver = $DriverOther.Trim()
        if ([string]::IsNullOrWhiteSpace($resolvedDriver)) {
            Write-Log "Driver is set to 'Other' but DriverOther is empty." -Type 3
            Exit-WithCode 1
        }
    }
    Write-Log "Using driver: '$resolvedDriver'"

    $extraAttributes = [ordered]@{}
    foreach ($line in ($AdditionalAttributes -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }
        if ($trimmed -notmatch '^([^=]+)=(.*)$') {
            Write-Log "Invalid AdditionalAttributes line (expected key=value): '$trimmed'" -Type 3
            Exit-WithCode 1
        }
        $extraAttributes[$Matches[1].Trim()] = $Matches[2].Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($Username)) {
        $extraAttributes['UID'] = $Username.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($Password)) {
        $extraAttributes['PWD'] = $Password
    }

    if ($TrustedConnection -eq 'Yes' -and (-not [string]::IsNullOrWhiteSpace($Username) -or -not [string]::IsNullOrWhiteSpace($Password))) {
        Write-Log "WARNING: Trusted Connection is set to Yes, but Username/Password were provided. Credentials will still be stored in the DSN." -Type 2
    }

    $views = @()
    switch ($Platform) {
        'Both'        { $views = @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32) }
        'Platform64'  { $views = @([Microsoft.Win32.RegistryView]::Registry64) }
        'Platform32'  { $views = @([Microsoft.Win32.RegistryView]::Registry32) }
    }

    $failed = $false
    foreach ($view in $views) {
        $archLabel = if ($view -eq [Microsoft.Win32.RegistryView]::Registry64) { '64-bit' } else { '32-bit' }
        Write-Log "Processing $archLabel ODBC registry hive."

        if (-not (Test-OdbcDriverInstalled -View $view -DriverName $resolvedDriver)) {
            Write-Log "ODBC driver '$resolvedDriver' is not installed for $archLabel (missing SOFTWARE\ODBC\ODBCINST.INI\$resolvedDriver)." -Type 3
            $failed = $true
            continue
        }

        $dsnKey = $null
        $dataSourcesKey = $null
        try {
            $dsnKey = Open-OdbcRegistryKey -View $view -SubKeyPath "SOFTWARE\ODBC\ODBC.INI\$DsnName" -Writable
            $dsnKey.SetValue('Driver', $resolvedDriver, [Microsoft.Win32.RegistryValueKind]::String)
            if (-not [string]::IsNullOrWhiteSpace($Description)) {
                $dsnKey.SetValue('Description', $Description, [Microsoft.Win32.RegistryValueKind]::String)
            }
            if (-not [string]::IsNullOrWhiteSpace($Server)) {
                $dsnKey.SetValue('Server', $Server, [Microsoft.Win32.RegistryValueKind]::String)
            }
            if (-not [string]::IsNullOrWhiteSpace($Database)) {
                $dsnKey.SetValue('Database', $Database, [Microsoft.Win32.RegistryValueKind]::String)
            }
            if ($TrustedConnection -eq 'Yes') {
                $dsnKey.SetValue('Trusted_Connection', 'Yes', [Microsoft.Win32.RegistryValueKind]::String)
            }
            foreach ($name in $extraAttributes.Keys) {
                $dsnKey.SetValue($name, [string]$extraAttributes[$name], [Microsoft.Win32.RegistryValueKind]::String)
            }

            $dataSourcesKey = Open-OdbcRegistryKey -View $view -SubKeyPath 'SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources' -Writable
            $dataSourcesKey.SetValue($DsnName, $resolvedDriver, [Microsoft.Win32.RegistryValueKind]::String)

            Write-Log "Created/updated $archLabel system DSN '$DsnName' with driver '$resolvedDriver'."
        }
        finally {
            if ($null -ne $dsnKey) { $dsnKey.Dispose() }
            if ($null -ne $dataSourcesKey) { $dataSourcesKey.Dispose() }
        }
    }

    if ($failed) {
        Write-Log 'One or more architectures failed. See log for details.' -Type 3
        Exit-WithCode 1
    }

    Write-Log 'ODBC system DSN creation completed successfully.'
    Exit-WithCode 0
}
catch {
    Write-Log "Unhandled error: $($_.Exception.Message)" -Type 3
    Exit-WithCode 1
}
