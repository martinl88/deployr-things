[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$AppID,

    [Parameter(Mandatory = $false)]
    [ValidateSet("machine", "user")]
    [string]$Scope,

    [Parameter(Mandatory = $false)]
    [switch]$AcceptPackageAgreements,

    [Parameter(Mandatory = $false)]
    [switch]$AcceptSourceAgreements,

    [Parameter(Mandatory = $false)]
    [bool]$Silent = $true,

    [Parameter(Mandatory = $false)]
    [string]$Source = "winget",

    [Parameter(Mandatory = $false)]
    [string]$LogFile = "$env:SystemDrive\_2P\Logs\WinGetApp_Install_$AppID.log"
)

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet(1, 2, 3)]
        [int]$Type = 1,

        [Parameter(Mandatory = $false)]
        [string]$Component = "WinGetApp"
    )

    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    $LogFileFolderPath = Split-Path -Path $LogFile -Parent

    if (!(Test-Path -Path $LogFileFolderPath)) {
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

    if ($Host.Name -ne "ConsoleHost") {
        $host.SetShouldExit($exitcode)
    }
    exit $exitcode
}

if ([string]::IsNullOrWhiteSpace($AppID)) {
    Write-Log -Message "ERROR: AppID parameter is required" -Type 3
    ExitWithCode -exitcode 1
}

Write-Log -Message "=====================================================" -Type 1
Write-Log -Message "Starting WinGet single app installer" -Type 1
Write-Log -Message "Application ID: $AppID" -Type 1
Write-Log -Message "Scope: $(if ($Scope) { $Scope } else { '(not set)' })" -Type 1
Write-Log -Message "Silent: $Silent" -Type 1
Write-Log -Message "Source: $Source" -Type 1
Write-Log -Message "Accept Package Agreements: $AcceptPackageAgreements" -Type 1
Write-Log -Message "Accept Source Agreements: $AcceptSourceAgreements" -Type 1
Write-Log -Message "=====================================================" -Type 1

$wingetExe = (Get-ChildItem -Path 'C:\Program Files\WindowsApps' -Recurse -Filter 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName

if (-not $wingetExe) {
    Write-Log -Message "ERROR: winget.exe was not found in C:\Program Files\WindowsApps" -Type 3
    ExitWithCode -exitcode 1
}

Write-Log -Message "Found winget.exe at: $wingetExe" -Type 1

$wingetArgs = @("install", $AppID)

if ($Silent) {
    $wingetArgs += "--silent"
}

if (-not [string]::IsNullOrWhiteSpace($Scope)) {
    $wingetArgs += "--scope"
    $wingetArgs += $Scope
}

if (-not [string]::IsNullOrWhiteSpace($Source)) {
    $wingetArgs += "--source"
    $wingetArgs += $Source
}

if ($AcceptPackageAgreements) {
    $wingetArgs += "--accept-package-agreements"
}

if ($AcceptSourceAgreements) {
    $wingetArgs += "--accept-source-agreements"
}

Write-Log -Message "Running: $wingetExe $($wingetArgs -join ' ')" -Type 1

try {
    $process = Start-Process -FilePath $wingetExe -ArgumentList $wingetArgs -Wait -NoNewWindow -PassThru

    if ($process.ExitCode -ne 0) {
        Write-Log -Message "ERROR: winget install for $AppID returned exit code $($process.ExitCode)" -Type 3
        ExitWithCode -exitcode $process.ExitCode
    }

    Write-Log -Message "Successfully installed application: $AppID with exit code $($process.ExitCode)" -Type 1
    ExitWithCode -exitcode $process.ExitCode
}
catch {
    Write-Log -Message "ERROR: Failed to install $AppID - $($_.Exception.Message)" -Type 3
    ExitWithCode -exitcode 1
}
