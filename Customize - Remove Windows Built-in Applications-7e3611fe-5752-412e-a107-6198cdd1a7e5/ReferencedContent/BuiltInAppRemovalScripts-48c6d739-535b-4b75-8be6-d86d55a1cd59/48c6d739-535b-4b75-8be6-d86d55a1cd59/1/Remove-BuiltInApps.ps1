#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$LogFile = 'C:\_2P\Logs\BuiltInAppRemoval.log',
    [ValidateSet('Both', 'Registry', 'Cache', 'None')]
    [string]$StartMenuCleanup = 'Both'
)

$ErrorActionPreference = 'Stop'
$script:LogFile = $LogFile

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet(1, 2, 3)]
        [int]$Type = 1
    )

    $folder = Split-Path -Path $script:LogFile -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    $time = Get-Date -Format 'HH:mm:ss.ffffff'
    $date = Get-Date -Format 'MM-dd-yyyy'
    "<![LOG[$Message]LOG]!><time=`"$time`" date=`"$date`" component=`"BuiltInAppRemoval`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">" | Out-File -Append -Encoding UTF8 -FilePath $script:LogFile
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

function Set-RegistryDWord {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    if ($PSCmdlet.ShouldProcess("$Path\$Name", 'Set DWord value')) {
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
    }
}

function Disable-ConsumerAppSuggestion {
    $cloudContentPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    Set-RegistryDWord -Path $cloudContentPath -Name 'DisableWindowsConsumerFeatures' -Value 1
    Set-RegistryDWord -Path $cloudContentPath -Name 'DisableCloudOptimizedContent' -Value 1
    Write-Log -Message 'Disabled consumer app suggestions and cloud-optimized content'
}

function Clear-DefaultUserStartMenuCache {
    $startMenuRelativePath = 'AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy'
    $defaultProfilePaths = @(
        'C:\Users\Default',
        'C:\Users\Public'
    )

    foreach ($profilePath in $defaultProfilePaths) {
        if (-not (Test-Path -LiteralPath $profilePath -PathType Container)) { continue }
        $hostPath = Join-Path -Path $profilePath -ChildPath $startMenuRelativePath
        if (-not (Test-Path -LiteralPath $hostPath -PathType Container)) { continue }
        foreach ($subFolder in @('TempState', 'LocalState')) {
            $target = Join-Path -Path $hostPath -ChildPath $subFolder
            if (Test-Path -LiteralPath $target -PathType Container) {
                try {
                    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
                    Write-Log -Message "Cleared $target"
                }
                catch {
                    Write-Log -Message "WARNING: Could not clear $target`: $($_.Exception.Message)" -Type 2
                }
            }
        }
    }
}

function Get-WinGetPath {
    $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    return Get-ChildItem -Path 'C:\Program Files\WindowsApps' -Recurse -Filter 'winget.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Remove-AppxApplication {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory = $true)][string]$AppId)

    if (-not $PSCmdlet.ShouldProcess($AppId, 'Remove installed and provisioned Appx packages')) { return }
    $pattern = "*$AppId*"
    $errors = [Collections.Generic.List[string]]::new()
    foreach ($package in @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue)) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log -Message "Removed installed package '$($package.PackageFullName)'"
        }
        catch {
            $errors.Add("Installed package '$($package.PackageFullName)': $($_.Exception.Message)")
        }
    }

    foreach ($package in @(Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like $pattern })) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
            Write-Log -Message "Removed provisioned package '$($package.PackageName)'"
        }
        catch {
            $errors.Add("Provisioned package '$($package.PackageName)': $($_.Exception.Message)")
        }
    }

    $remainingInstalled = @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue)
    $remainingProvisioned = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like $pattern })
    if ($remainingInstalled.Count -gt 0 -or $remainingProvisioned.Count -gt 0) {
        $errors.Add("Verification found $($remainingInstalled.Count) installed and $($remainingProvisioned.Count) provisioned package(s) remaining.")
    }

    if ($errors.Count -gt 0) {
        throw ($errors -join ' ')
    }
}

function Remove-WinGetApplication {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string[]]$AppIds,
        [Parameter(Mandatory = $true)][string]$WinGetPath
    )

    if (-not $PSCmdlet.ShouldProcess(($AppIds -join ', '), 'Uninstall WinGet packages')) { return }
    foreach ($appId in $AppIds) {
        Write-Log -Message "Running WinGet uninstall for '$appId'"
        $output = @(& $WinGetPath uninstall --id $appId --exact --silent --accept-source-agreements --disable-interactivity 2>&1)
        foreach ($line in $output) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                Write-Log -Message "WinGet: $line"
            }
        }
    }

    $remaining = [Collections.Generic.List[string]]::new()
    foreach ($appId in $AppIds) {
        $output = @(& $WinGetPath list --id $appId --exact --accept-source-agreements --disable-interactivity 2>&1)
        if (($output -join "`n") -match "(?im)^.+\s{2,}$([regex]::Escape($appId))(\s{2,}|$)") {
            $remaining.Add($appId)
        }
    }
    if ($remaining.Count -gt 0) {
        throw "WinGet verification found the following package ID(s) remaining: $($remaining -join ', ')."
    }
}

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Verbose "DeployR.Utility could not be imported: $($_.Exception.Message)"
}

$appDefinitions = @'
[{"Option":"RemoveMicrosoftWindowsAlarms","FriendlyName":"Alarms & Clock","AppId":["Microsoft.WindowsAlarms"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftBingNews","FriendlyName":"Bing News","AppId":["Microsoft.BingNews"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftBingSearch","FriendlyName":"Bing Search","AppId":["Microsoft.BingSearch"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftBingWeather","FriendlyName":"Bing Weather","AppId":["Microsoft.BingWeather"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftWindowsCalculator","FriendlyName":"Calculator","AppId":["Microsoft.WindowsCalculator"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftWindowsCamera","FriendlyName":"Camera","AppId":["Microsoft.WindowsCamera"],"Method":"Appx","Default":false},{"Option":"RemoveClipchampClipchamp","FriendlyName":"Clipchamp","AppId":["Clipchamp.Clipchamp"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftWindowsCrossDevice","FriendlyName":"Cross Device Experience","AppId":["MicrosoftWindows.CrossDevice"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftWindowsDevHome","FriendlyName":"Dev Home","AppId":["Microsoft.Windows.DevHome"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftWindowsFeedbackHub","FriendlyName":"Feedback Hub","AppId":["Microsoft.WindowsFeedbackHub"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftGetHelp","FriendlyName":"Get Help","AppId":["Microsoft.GetHelp"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftZuneMusic","FriendlyName":"Media Player","AppId":["Microsoft.ZuneMusic"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftEdge","FriendlyName":"Microsoft Edge","AppId":["Microsoft.Edge","XPFFTQ037JWMHS"],"Method":"WinGet","Default":false},{"Option":"RemoveMicrosoftWindowsStore","FriendlyName":"Microsoft Store","AppId":["Microsoft.WindowsStore"],"Method":"Appx","Default":false},{"Option":"RemoveMSTeams","FriendlyName":"Microsoft Teams (New)","AppId":["MSTeams"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftTodos","FriendlyName":"Microsoft To Do","AppId":["Microsoft.Todos"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftWindowsNotepad","FriendlyName":"Notepad","AppId":["Microsoft.WindowsNotepad"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftMicrosoftOfficeHub","FriendlyName":"Office Hub","AppId":["Microsoft.MicrosoftOfficeHub"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftOneDrive","FriendlyName":"OneDrive","AppId":["Microsoft.OneDrive"],"Method":"WinGet","Default":false},{"Option":"RemoveMicrosoftOutlookForWindows","FriendlyName":"Outlook for Windows","AppId":["Microsoft.OutlookForWindows"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftPaint","FriendlyName":"Paint","AppId":["Microsoft.Paint"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftYourPhone","FriendlyName":"Phone Link","AppId":["Microsoft.YourPhone"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftWindowsPhotos","FriendlyName":"Photos","AppId":["Microsoft.Windows.Photos"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftPowerAutomateDesktop","FriendlyName":"Power Automate","AppId":["Microsoft.PowerAutomateDesktop"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftCorporationIIQuickAssist","FriendlyName":"Quick Assist","AppId":["MicrosoftCorporationII.QuickAssist"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftScreenSketch","FriendlyName":"Snipping Tool","AppId":["Microsoft.ScreenSketch"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftMicrosoftSolitaireCollection","FriendlyName":"Solitaire Collection","AppId":["Microsoft.MicrosoftSolitaireCollection"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftWindowsSoundRecorder","FriendlyName":"Sound Recorder","AppId":["Microsoft.WindowsSoundRecorder"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftMicrosoftStickyNotes","FriendlyName":"Sticky Notes","AppId":["Microsoft.MicrosoftStickyNotes"],"Method":"Appx","Default":true},{"Option":"RemoveMicrosoftStartExperiencesApp","FriendlyName":"Widgets Experience","AppId":["Microsoft.StartExperiencesApp"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftWidgetsPlatformRuntime","FriendlyName":"Widgets Platform Runtime","AppId":["Microsoft.WidgetsPlatformRuntime"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftWindowsTerminal","FriendlyName":"Windows Terminal","AppId":["Microsoft.WindowsTerminal"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftWindowsClientWebExperience","FriendlyName":"Windows Web Experience Pack","AppId":["MicrosoftWindows.Client.WebExperience"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftGamingApp","FriendlyName":"Xbox Gaming App","AppId":["Microsoft.GamingApp"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftXboxGamingOverlay","FriendlyName":"Xbox Gaming Overlay","AppId":["Microsoft.XboxGamingOverlay"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftXboxIdentityProvider","FriendlyName":"Xbox Identity Provider","AppId":["Microsoft.XboxIdentityProvider"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftXboxSpeechToTextOverlay","FriendlyName":"Xbox Speech To Text","AppId":["Microsoft.XboxSpeechToTextOverlay"],"Method":"Appx","Default":false},{"Option":"RemoveMicrosoftXboxTCUI","FriendlyName":"Xbox TCUI Framework","AppId":["Microsoft.Xbox.TCUI"],"Method":"Appx","Default":false}]
'@ | ConvertFrom-Json

foreach ($app in $appDefinitions) {
    $value = Get-TaskSequenceValue -Name $app.Option
    $app | Add-Member -NotePropertyName Selected -NotePropertyValue $(if ($null -eq $value) { [bool]$app.Default } else { [Convert]::ToBoolean($value) })
}

$selectedApps = @($appDefinitions | Where-Object Selected)
$failures = [Collections.Generic.List[string]]::new()
$winGetPath = $null

$tsStartMenuCleanup = Get-TaskSequenceValue -Name 'StartMenuCleanup'
if ($null -ne $tsStartMenuCleanup) {
    $StartMenuCleanup = $tsStartMenuCleanup
}

Write-Log -Message '====================================================='
Write-Log -Message "Starting Windows built-in application removal ($($selectedApps.Count) selected)"
Write-Log -Message "Start menu cleanup mode: $StartMenuCleanup"
Write-Log -Message '====================================================='
Write-Progress -Activity 'Built-in Application Removal' -Status 'Starting application removal...' -PercentComplete 0

if (@($selectedApps | Where-Object Method -eq 'WinGet').Count -gt 0) {
    $winGetPath = Get-WinGetPath
    if (-not $winGetPath) {
        $failures.Add('WinGet is required for one or more selected applications but winget.exe was not found.')
    }
}

$currentApp = 0
foreach ($app in $appDefinitions) {
    if (-not $app.Selected) {
        Write-Log -Message "$($app.FriendlyName): skipped"
        continue
    }

    $currentApp++
    $basePercent = if ($selectedApps.Count -gt 0) { [int](($currentApp - 1) * 100.0 / $selectedApps.Count) } else { 0 }
    Write-Progress -Activity 'Built-in Application Removal' -Status "Removing app $currentApp of $($selectedApps.Count): $($app.FriendlyName)" -PercentComplete $basePercent

    try {
        Write-Log -Message "$($app.FriendlyName): removing via $($app.Method)"
        if ($app.Method -eq 'Appx') {
            Remove-AppxApplication -AppId $app.AppId[0]
        }
        elseif ($winGetPath) {
            Remove-WinGetApplication -AppIds @($app.AppId) -WinGetPath $winGetPath
        }
        else {
            throw 'winget.exe was not found.'
        }
        Write-Log -Message "$($app.FriendlyName): removed"
    }
    catch {
        $message = "$($app.FriendlyName): $($_.Exception.Message)"
        $failures.Add($message)
        Write-Log -Message "ERROR: $message" -Type 3
    }

    $percentComplete = [int]($currentApp * 100.0 / $selectedApps.Count)
    Write-Progress -Activity 'Built-in Application Removal' -Status "Processed app $currentApp of $($selectedApps.Count): $($app.FriendlyName)" -PercentComplete $percentComplete
}

Write-Progress -Activity 'Built-in Application Removal' -Status 'Application removal completed' -PercentComplete 100
Write-Progress -Activity 'Built-in Application Removal' -Completed

if ($StartMenuCleanup -in @('Registry', 'Both')) {
    try {
        Disable-ConsumerAppSuggestion
    }
    catch {
        $message = "Failed to disable consumer app suggestions: $($_.Exception.Message)"
        $failures.Add($message)
        Write-Log -Message "ERROR: $message" -Type 3
    }
}

if ($StartMenuCleanup -in @('Cache', 'Both')) {
    Clear-DefaultUserStartMenuCache
}

if ($failures.Count -gt 0) {
    Write-Log -Message "Built-in application removal completed with $($failures.Count) failure(s)." -Type 3
    Exit-WithCode -ExitCode 1
}

Write-Log -Message 'Windows built-in application removal completed successfully.'
Exit-WithCode -ExitCode 0
