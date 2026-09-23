[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DownloadUrl = "https://packages.vmware.com/tools/esx/latest/windows/x64/",

    [Parameter(Mandatory = $false)]
    [string]$InstallArgs = '/S /v"/qn REBOOT=R ADDLOCAL=ALL"',

    [Parameter(Mandatory = $false)]
    [int]$Timeout = 1800,

    [Parameter(Mandatory = $false)]
    [string]$LogFile = "C:\_2P\Logs\VMwareTools_Install.log"
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
        [string]$Component = "VMwareTools"
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

Write-Log -Message "=====================================================" -Type 1
Write-Log -Message "Starting VMware Tools installer" -Type 1
Write-Log -Message "Download URL: $DownloadUrl" -Type 1
Write-Log -Message "Install Args: $InstallArgs" -Type 1
Write-Log -Message "=====================================================" -Type 1

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$tempFolder = Join-Path -Path $env:TEMP -ChildPath "VMwareTools_$(New-Guid)"
New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null

$installerPath = $null

try {
    Write-Log -Message "Fetching directory listing from $DownloadUrl" -Type 1

    $response = Invoke-WebRequest -Uri $DownloadUrl -UseBasicParsing -TimeoutSec $Timeout -ErrorAction Stop
    $links = $response.Links | Where-Object { $_.href -match 'VMware-tools-.*-x64\.exe$' }

    if (-not $links) {
        Write-Log -Message "ERROR: Could not find a VMware Tools x64 installer link at $DownloadUrl" -Type 3
        Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        ExitWithCode -exitcode 1
    }

    $installerFileName = $links[0].href
    if ($installerFileName -notmatch '^https?://') {
        $baseUri = [System.Uri]$DownloadUrl
        $installerUrl = [System.Uri]::new($baseUri, $installerFileName).AbsoluteUri
    }
    else {
        $installerUrl = $installerFileName
    }

    $installerFileName = Split-Path -Path $installerUrl -Leaf
    $installerPath = Join-Path -Path $tempFolder -ChildPath $installerFileName

    Write-Log -Message "Found installer: $installerUrl" -Type 1
    Write-Log -Message "Downloading to $installerPath" -Type 1

    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec $Timeout -ErrorAction Stop

    if (-not (Test-Path -Path $installerPath)) {
        throw "Download completed but installer was not found at $installerPath"
    }

    $fileSize = (Get-Item -Path $installerPath).Length
    Write-Log -Message "Downloaded $installerFileName ($fileSize bytes)" -Type 1

    Write-Log -Message "Running: $installerPath $InstallArgs" -Type 1

    $process = Start-Process -FilePath $installerPath -ArgumentList $InstallArgs -NoNewWindow -PassThru
    $completed = $process.WaitForExit($Timeout * 1000)

    if (-not $completed) {
        Write-Log -Message "ERROR: VMware Tools installer exceeded timeout of $Timeout seconds" -Type 3
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        ExitWithCode -exitcode 1
    }

    if ($process.ExitCode -ne 0) {
        Write-Log -Message "ERROR: VMware Tools installer returned exit code $($process.ExitCode)" -Type 3
        ExitWithCode -exitcode $process.ExitCode
    }

    Write-Log -Message "Successfully installed VMware Tools" -Type 1
    ExitWithCode -exitcode 0
}
catch {
    Write-Log -Message "ERROR: $($_.Exception.Message)" -Type 3
    ExitWithCode -exitcode 1
}
finally {
    if ($tempFolder -and (Test-Path -Path $tempFolder)) {
        try {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log -Message "Cleaned up temp folder $tempFolder" -Type 1
        }
        catch {
            Write-Log -Message "WARNING: Could not remove temp folder $tempFolder - $($_.Exception.Message)" -Type 2
        }
    }
}
