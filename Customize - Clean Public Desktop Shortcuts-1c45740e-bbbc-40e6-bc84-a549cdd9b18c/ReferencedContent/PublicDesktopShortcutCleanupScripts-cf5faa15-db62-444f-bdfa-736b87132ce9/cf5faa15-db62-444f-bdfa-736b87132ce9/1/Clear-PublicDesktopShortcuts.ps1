[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [AllowEmptyString()]
    [string]$ShortcutsToKeep = "Microsoft Edge`r`nGoogle Chrome",
    [switch]$DisableEdgeDesktopShortcutCreation,
    [string]$DesktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory'),
    [string]$LogFile = 'C:\_2P\Logs\PublicDesktopShortcutCleanup.log',
    [string]$EdgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
)

$ErrorActionPreference = 'Stop'
$script:PublicDesktopCleanupLogFile = $LogFile

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
    $folder = Split-Path -Path $script:PublicDesktopCleanupLogFile -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $logMessage = "<![LOG[$Message]LOG]!><time=`"$time`" date=`"$date`" component=`"PublicDesktopShortcutCleanup`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $logMessage | Out-File -Append -Encoding UTF8 -FilePath $script:PublicDesktopCleanupLogFile
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
        if ($null -ne $item) {
            return [string]$item.Value
        }
    }
    catch {
        return $null
    }

    return $null
}

function Set-RegistryDWord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [int]$Value
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null

    $appliedValue = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    if ($appliedValue -ne $Value) {
        throw "Registry value verification failed for '$Path\$Name'. Expected $Value, received $appliedValue."
    }
}

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Verbose "DeployR.Utility could not be imported: $($_.Exception.Message)"
}

if (Get-Module -Name 'DeployR.Utility') {
    $taskSequenceValue = Get-TaskSequenceValue -Name 'ShortcutsToKeep'
    if ($null -ne $taskSequenceValue) {
        $ShortcutsToKeep = $taskSequenceValue
    }

    $taskSequenceValue = Get-TaskSequenceValue -Name 'DisableEdgeDesktopShortcutCreation'
    if ($null -ne $taskSequenceValue) {
        $DisableEdgeDesktopShortcutCreation = [System.Convert]::ToBoolean($taskSequenceValue)
    }
}

try {
    Write-Log -Message '====================================================='
    Write-Log -Message 'Starting Public Desktop shortcut cleanup'
    Write-Log -Message '====================================================='

    if ($DisableEdgeDesktopShortcutCreation) {
        if ($PSCmdlet.ShouldProcess("$EdgePolicyPath\DesktopShortcutCreationEnabled", 'Set Microsoft Edge policy to 0')) {
            Set-RegistryDWord -Path $EdgePolicyPath -Name 'DesktopShortcutCreationEnabled' -Value 0
            Write-Log -Message 'Disabled Microsoft Edge desktop shortcut creation.'
        }
        else {
            Write-Log -Message 'Skipped Microsoft Edge desktop shortcut creation policy.'
        }
    }
    else {
        Write-Log -Message 'Microsoft Edge desktop shortcut creation policy: unchanged.'
    }

    if ([string]::IsNullOrWhiteSpace($DesktopPath)) {
        throw 'The Public Desktop path could not be resolved.'
    }
    if (-not (Test-Path -LiteralPath $DesktopPath -PathType Container)) {
        throw "The Public Desktop folder was not found at '$DesktopPath'."
    }

    $allowedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    @($ShortcutsToKeep -split '[\r\n,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | ForEach-Object {
        $normalizedName = $_ -replace '(?i)\.(lnk|url)$', ''
        if (-not [string]::IsNullOrWhiteSpace($normalizedName)) {
            $null = $allowedNames.Add($normalizedName)
        }
    }

    if ($allowedNames.Count -eq 0) {
        Write-Log -Message 'No shortcuts are configured to be retained.' -Type 2
    }
    else {
        Write-Log -Message "Shortcuts to keep: $([string]::Join(', ', $allowedNames))"
    }

    $shortcuts = @(
        Get-ChildItem -LiteralPath $DesktopPath -File |
            Where-Object { $_.Extension -in @('.lnk', '.url') }
    )

    $removedCount = 0
    $retainedCount = 0
    foreach ($shortcut in $shortcuts) {
        if ($allowedNames.Contains($shortcut.BaseName)) {
            Write-Log -Message "Retained shortcut: $($shortcut.Name)"
            $retainedCount++
            continue
        }

        if ($PSCmdlet.ShouldProcess($shortcut.FullName, 'Remove Public Desktop shortcut')) {
            Remove-Item -LiteralPath $shortcut.FullName -Force
            Write-Log -Message "Removed shortcut: $($shortcut.Name)"
            $removedCount++
        }
        else {
            Write-Log -Message "Skipped shortcut: $($shortcut.Name)"
        }
    }

    Write-Log -Message "Cleanup completed. Removed: $removedCount; retained: $retainedCount; discovered: $($shortcuts.Count)."
    Write-Log -Message '====================================================='
    Exit-WithCode -ExitCode 0
}
catch {
    Write-Log -Message "ERROR: $($_.Exception.Message)" -Type 3
    Exit-WithCode -ExitCode 1
}
