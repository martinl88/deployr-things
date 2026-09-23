[CmdletBinding()]
param()

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    # Module is not available outside of the task sequence environment
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [int]$Type = 1
    )

    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    $LogFile = "$env:SystemDrive\_2P\Logs\WinGetApps_Install.log"
    $LogFileFolderPath = Split-Path -Path $LogFile -Parent

    if (!(Test-Path -Path $LogFileFolderPath)) {
        New-Item -ItemType Directory -Path $LogFileFolderPath -Force | Out-Null
    }

    $LogMessage = "<![LOG[$Message]LOG]!><time=`"$Time`" date=`"$Date`" component=`"WinGetApps`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile

    Write-Host $Message
}

function ExitWithCode {
    param (
        $exitcode
    )

    $host.SetShouldExit($exitcode)
    exit
}

if (Get-Module -Name "DeployR.Utility") {
    $WingetAppIDs = ${TSEnv:WingetAppIDs}
    $WingetScope = ${TSEnv:WingetScope}
    $WingetAcceptPackageAgreements = ${TSEnv:WingetAcceptPackageAgreements}
    $WingetAcceptSourceAgreements = ${TSEnv:WingetAcceptSourceAgreements}
}
else {
    $WingetAppIDs = "Mozilla.Firefox"
    $WingetScope = ""
    $WingetAcceptPackageAgreements = "true"
    $WingetAcceptSourceAgreements = "true"
}

Write-Log -Message "=====================================================" -Type 1
Write-Log -Message "Starting WinGet Application Installer" -Type 1
Write-Log -Message "=====================================================" -Type 1
Write-Log -Message "Install Scope: $(if ($WingetScope) { $WingetScope } else { '(not set)' })" -Type 1
Write-Log -Message "Accept Package Agreements: $WingetAcceptPackageAgreements" -Type 1
Write-Log -Message "Accept Source Agreements: $WingetAcceptSourceAgreements" -Type 1
Write-Log -Message "Application IDs: $WingetAppIDs" -Type 1

$wingetExe = (Get-ChildItem -Path 'C:\Program Files\WindowsApps' -Recurse -Filter 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName

if (-not $wingetExe) {
    Write-Log -Message "ERROR: winget.exe was not found in C:\Program Files\WindowsApps" -Type 3
    ExitWithCode -exitcode 1
}

Write-Log -Message "Found winget.exe at: $wingetExe" -Type 1

$wingetArgs = @(
    "install",
    "--silent",
    "--source",
    "winget"
)

if (-not [string]::IsNullOrWhiteSpace($WingetScope)) {
    $wingetArgs += "--scope"
    $wingetArgs += $WingetScope
}

if ($WingetAcceptPackageAgreements -eq "true") {
    $wingetArgs += "--accept-package-agreements"
}

if ($WingetAcceptSourceAgreements -eq "true") {
    $wingetArgs += "--accept-source-agreements"
}

$appIDs = $WingetAppIDs -split '[\r\n,;]+' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

if ($appIDs.Count -eq 0) {
    Write-Log -Message "ERROR: No application IDs were provided" -Type 3
    ExitWithCode -exitcode 1
}

$exitCode = 0

foreach ($id in $appIDs) {
    Write-Log -Message "Installing application: $id" -Type 1

    try {
        $process = Start-Process -FilePath $wingetExe -ArgumentList ($wingetArgs + $id) -Wait -NoNewWindow -PassThru

        if ($process.ExitCode -ne 0) {
            Write-Log -Message "WARNING: winget install for $id returned exit code $($process.ExitCode)" -Type 2
            $exitCode = $process.ExitCode
        }
        else {
            Write-Log -Message "Successfully installed application: $id with exit code $($process.ExitCode)" -Type 1
        }
    }
    catch {
        Write-Log -Message "ERROR: Failed to install $id - $($_.Exception.Message)" -Type 3
        $exitCode = 1
    }
}

Write-Log -Message "=====================================================" -Type 1
Write-Log -Message "WinGet Application Installer completed with exit code $exitCode" -Type 1
Write-Log -Message "=====================================================" -Type 1

ExitWithCode -exitcode $exitCode
