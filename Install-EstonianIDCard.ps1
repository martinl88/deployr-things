[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$LogFile = "C:\windows\Temp\EstonianIDCard_Install.log",

    [Parameter(Mandatory = $false)]
    [string]$OpenEIDUrl = "https://www.id.ee/artikkel/paigalda-id-tarkvara/",

    [Parameter(Mandatory = $false)]
    [string]$OpenEIDArgs = "/passive /quiet /norestart IconsDesktop=0 RunQesteidutil=0",

    [Parameter(Mandatory = $false)]
    [string]$SmartCardRepo = "open-eid/smart-card-removal",

    [Parameter(Mandatory = $false)]
    [int]$Timeout = 1800
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
        [string]$Component = "EstonianIDCard"
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
Write-Log -Message "Starting Estonian ID-Card installer" -Type 1
Write-Log -Message "OpenEIDUrl: $OpenEIDUrl" -Type 1
Write-Log -Message "OpenEIDArgs: $OpenEIDArgs" -Type 1
Write-Log -Message "SmartCardRepo: $SmartCardRepo" -Type 1
Write-Log -Message "=====================================================" -Type 1

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$tempFolder = Join-Path -Path $env:TEMP -ChildPath "EstonianIDCard_$(New-Guid)"
New-Item -ItemType Directory -Path $tempFolder -Force | Out-Null

$openEidSuccess = $false
$smartCardSuccess = $false
$lastNonZeroExitCode = 0

try {
    # --- Install Open-EID (ID-card software) ---
    try {
        Write-Log -Message "Open-EID: Starting discovery" -Component "OpenEID"

        $openEidUri = $null
        if ([System.Uri]::IsWellFormedUriString($OpenEIDUrl, [System.UriKind]::Absolute)) {
            $openEidUri = [System.Uri]$OpenEIDUrl
        }

        if ($openEidUri -and $openEidUri.AbsolutePath -match '\.exe$') {
            $installerUrl = $OpenEIDUrl
            $installerFileName = Split-Path -Path $openEidUri.AbsolutePath -Leaf
            Write-Log -Message "Open-EID: Using direct URL $OpenEIDUrl" -Component "OpenEID"
        }
        else {
            Write-Log -Message "Open-EID: Fetching $OpenEIDUrl" -Component "OpenEID"

            $invokeParams = @{ Uri = $OpenEIDUrl; ErrorAction = 'Stop'; TimeoutSec = $Timeout }
            if ($PSVersionTable.PSVersion.Major -lt 6) { $invokeParams['UseBasicParsing'] = $true }
            $page = Invoke-WebRequest @invokeParams

            $exeLink = $page.Links |
                Where-Object { $_.href -and ($_.href -match '\.exe$') -and ($_.outerHTML -match 'Open-EID') } |
                Select-Object -First 1 -ExpandProperty href

            if (-not $exeLink) {
                throw "Could not find Open-EID installer link on page $OpenEIDUrl"
            }

            if ($exeLink -notmatch '^https?://') {
                $baseUri = [System.Uri]$OpenEIDUrl
                $installerUrl = [System.Uri]::new($baseUri, $exeLink).AbsoluteUri
            }
            else {
                $installerUrl = $exeLink
            }

            $installerFileName = Split-Path -Path ([System.Uri]$installerUrl).AbsolutePath -Leaf
            Write-Log -Message "Open-EID: Found installer URL $installerUrl" -Component "OpenEID"
        }

        $installerPath = Join-Path -Path $tempFolder -ChildPath $installerFileName

        Write-Log -Message "Open-EID: Downloading to $installerPath" -Component "OpenEID"

        $downloadParams = @{ Uri = $installerUrl; OutFile = $installerPath; ErrorAction = 'Stop'; TimeoutSec = $Timeout }
        if ($PSVersionTable.PSVersion.Major -lt 6) { $downloadParams['UseBasicParsing'] = $true }
        Invoke-WebRequest @downloadParams

        if (-not (Test-Path -Path $installerPath)) {
            throw "Download completed but Open-EID installer was not found at $installerPath"
        }

        $fileSize = (Get-Item -Path $installerPath).Length
        Write-Log -Message "Open-EID: Downloaded $installerFileName ($fileSize bytes)" -Component "OpenEID"

        $argumentList = $OpenEIDArgs -split ' '
        Write-Log -Message "Open-EID: Running $installerPath $OpenEIDArgs" -Component "OpenEID"

        $process = Start-Process -FilePath $installerPath -ArgumentList $argumentList -NoNewWindow -PassThru
        $completed = $process.WaitForExit($Timeout * 1000)

        if (-not $completed) {
            Write-Log -Message "Open-EID: Installer exceeded timeout of $Timeout seconds" -Type 3 -Component "OpenEID"
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $lastNonZeroExitCode = 1
        }
        elseif ($process.ExitCode -ne 0) {
            Write-Log -Message "Open-EID: Installer returned exit code $($process.ExitCode)" -Type 3 -Component "OpenEID"
            $lastNonZeroExitCode = $process.ExitCode
        }
        else {
            Write-Log -Message "Open-EID: Installer completed successfully" -Component "OpenEID"
            $openEidSuccess = $true
        }
    }
    catch {
        Write-Log -Message "Open-EID: ERROR: $($_.Exception.Message)" -Type 3 -Component "OpenEID"
        $lastNonZeroExitCode = 1
    }

    # --- Install SmartCardRemoval service ---
    try {
        Write-Log -Message "SmartCardRemoval: Starting discovery" -Component "SmartCardRemoval"

        $releasesApi = "https://api.github.com/repos/$SmartCardRepo/releases"
        $headers = @{ 'User-Agent' = 'DeployR-EstonianIDCard' }

        $releases = Invoke-RestMethod -Uri $releasesApi -Headers $headers -ErrorAction Stop -TimeoutSec $Timeout
        if (-not $releases -or $releases.Count -eq 0) {
            throw "No GitHub releases found at $releasesApi"
        }

        $latestTag = $releases[0].tag_name
        $msiUrl = "https://github.com/$SmartCardRepo/releases/download/$latestTag/SmartCardRemoval.msi"
        $msiFileName = Split-Path -Path ([System.Uri]$msiUrl).AbsolutePath -Leaf
        $msiPath = Join-Path -Path $tempFolder -ChildPath $msiFileName

        Write-Log -Message "SmartCardRemoval: Downloading $msiUrl to $msiPath" -Component "SmartCardRemoval"

        $downloadParams = @{ Uri = $msiUrl; OutFile = $msiPath; ErrorAction = 'Stop'; TimeoutSec = $Timeout }
        if ($PSVersionTable.PSVersion.Major -lt 6) { $downloadParams['UseBasicParsing'] = $true }
        Invoke-WebRequest @downloadParams

        if (-not (Test-Path -Path $msiPath)) {
            throw "Download completed but SmartCardRemoval MSI was not found at $msiPath"
        }

        $fileSize = (Get-Item -Path $msiPath).Length
        Write-Log -Message "SmartCardRemoval: Downloaded $msiFileName ($fileSize bytes)" -Component "SmartCardRemoval"

        Write-Log -Message "SmartCardRemoval: Running msiexec /i $msiPath /passive /qn" -Component "SmartCardRemoval"

        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', $msiPath, '/passive', '/qn' -NoNewWindow -PassThru
        $completed = $process.WaitForExit($Timeout * 1000)

        if (-not $completed) {
            Write-Log -Message "SmartCardRemoval: Installer exceeded timeout of $Timeout seconds" -Type 3 -Component "SmartCardRemoval"
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $lastNonZeroExitCode = 1
        }
        elseif ($process.ExitCode -ne 0) {
            Write-Log -Message "SmartCardRemoval: Installer returned exit code $($process.ExitCode)" -Type 3 -Component "SmartCardRemoval"
            $lastNonZeroExitCode = $process.ExitCode
        }
        else {
            Write-Log -Message "SmartCardRemoval: Installer completed successfully" -Component "SmartCardRemoval"
            $smartCardSuccess = $true
        }
    }
    catch {
        Write-Log -Message "SmartCardRemoval: ERROR: $($_.Exception.Message)" -Type 3 -Component "SmartCardRemoval"
        $lastNonZeroExitCode = 1
    }
}
finally {
    if ($tempFolder -and (Test-Path -Path $tempFolder)) {
        try {
            Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log -Message "Cleaned up temp folder $tempFolder" -Component "EstonianIDCard"
        }
        catch {
            Write-Log -Message "WARNING: Could not remove temp folder $tempFolder - $($_.Exception.Message)" -Type 2 -Component "EstonianIDCard"
        }
    }
}

if ($openEidSuccess -or $smartCardSuccess) {
    Write-Log -Message "At least one component installed successfully. Returning exit code 0." -Component "EstonianIDCard"
    ExitWithCode -exitcode 0
}
else {
    Write-Log -Message "Both components failed. Returning exit code $lastNonZeroExitCode." -Type 3 -Component "EstonianIDCard"
    ExitWithCode -exitcode $lastNonZeroExitCode
}
