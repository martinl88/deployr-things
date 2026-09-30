#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [switch]$DisableTelemetry,
    [switch]$DisableWindowsSuggestions,
    [switch]$DisableLocationServices,
    [switch]$DisableFindMyDevice,
    [switch]$DisableLockscreenTips,
    [switch]$DisableDesktopSpotlight,
    [switch]$DisableEdgeAds,
    [switch]$DisableSettings365Ads,
    [string]$LogFile = 'C:\_2P\Logs\PrivacySettings.log',
    [string]$DefaultUserHive = 'C:\Users\Default\NTUSER.DAT',
    [string]$DefaultUserMountPoint = 'DeployRPrivacyDefault'
)

$ErrorActionPreference = 'Stop'
$script:PrivacySettingsLogFile = $LogFile

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
    $folder = Split-Path -Path $script:PrivacySettingsLogFile -Parent
    if ($folder -and -not (Test-Path -Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $logMessage = "<![LOG[$Message]LOG]!><time=`"$time`" date=`"$date`" component=`"PrivacySettings`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $logMessage | Out-File -Append -Encoding UTF8 -FilePath $script:PrivacySettingsLogFile
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

function Remove-RegistryValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (Test-Path -Path $Path) {
        Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
    }
}

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    Write-Verbose "DeployR.Utility could not be imported: $($_.Exception.Message)"
}

$optionNames = @(
    'DisableTelemetry',
    'DisableWindowsSuggestions',
    'DisableLocationServices',
    'DisableFindMyDevice',
    'DisableLockscreenTips',
    'DisableDesktopSpotlight',
    'DisableEdgeAds',
    'DisableSettings365Ads'
)

if (Get-Module -Name 'DeployR.Utility') {
    foreach ($optionName in $optionNames) {
        $value = Get-TaskSequenceValue -Name $optionName
        if ($null -ne $value) {
            Set-Variable -Name $optionName -Value ([System.Convert]::ToBoolean($value))
        }
    }
}

$cdmPath = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$explorerAdvancedPath = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

$settings = @(
    [PSCustomObject]@{
        Option  = 'DisableTelemetry'
        Enabled = $DisableTelemetry
        Entries = @(
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name = 'HasAccepted'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Input\TIPC'; Name = 'Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Value = 1 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Value = 1 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\InputPersonalization\TrainedDataStore'; Name = 'HarvestContacts'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Personalization\Settings'; Name = 'AcceptedPrivacyPolicy'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $explorerAdvancedPath; Name = 'Start_TrackProgs'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Siuf\Rules'; Name = 'PeriodInNanoSeconds'; Value = $null },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'PersonalizationReportingEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'DiagnosticData'; Value = 0 }
        )
    },
    [PSCustomObject]@{
        Option  = 'DisableWindowsSuggestions'
        Enabled = $DisableWindowsSuggestions
        Entries = @(
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SubscribedContent-310093Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SubscribedContent-338388Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SubscribedContent-338389Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SubscribedContent-338393Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SubscribedContent-353694Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SubscribedContent-353696Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SubscribedContent-353698Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SystemPaneSuggestionsEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SoftLandingEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SilentInstalledAppsEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $explorerAdvancedPath; Name = 'Start_IrisRecommendations'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $explorerAdvancedPath; Name = 'ShowSyncProviderNotifications'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $explorerAdvancedPath; Name = 'Start_AccountNotifications'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications'; Name = 'EnableAccountNotifications'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested'; Name = 'Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Mobility'; Name = 'OptedIn'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.BackupReminder'; Name = 'Enabled'; Value = 0 }
        )
    },
    [PSCustomObject]@{
        Option  = 'DisableLocationServices'
        Enabled = $DisableLocationServices
        Entries = @(
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; Name = 'DisableLocation'; Value = 1 }
        )
    },
    [PSCustomObject]@{
        Option  = 'DisableFindMyDevice'
        Enabled = $DisableFindMyDevice
        Entries = @(
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\FindMyDevice'; Name = 'AllowFindMyDevice'; Value = 0 }
        )
    },
    [PSCustomObject]@{
        Option  = 'DisableLockscreenTips'
        Enabled = $DisableLockscreenTips
        Entries = @(
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'SubscribedContent-338387Enabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = $cdmPath; Name = 'RotatingLockScreenOverlayEnabled'; Value = 0 }
        )
    },
    [PSCustomObject]@{
        Option  = 'DisableDesktopSpotlight'
        Enabled = $DisableDesktopSpotlight
        Entries = @(
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableSpotlightCollectionOnDesktop'; Value = 1 },
            [PSCustomObject]@{ Hive = 'HKCU'; Path = 'Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'; Name = '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}'; Value = $null }
        )
    },
    [PSCustomObject]@{
        Option  = 'DisableEdgeAds'
        Enabled = $DisableEdgeAds
        Entries = @(
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'NewTabPageContentEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'NewTabPageHideDefaultTopSites'; Value = 1 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'EdgeShoppingAssistantEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'TabServicesEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'AlternateErrorPagesEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'UserFeedbackAllowed'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'ShowRecommendationsEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'WalletDonationEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'HideFirstRunExperience'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'DefaultBrowserSettingEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'DefaultBrowserSettingsCampaignEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'SpotlightExperiencesAndRecommendationsEnabled'; Value = 0 },
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Edge'; Name = 'ShowAcrobatSubscriptionButton'; Value = 0 }
        )
    },
    [PSCustomObject]@{
        Option  = 'DisableSettings365Ads'
        Enabled = $DisableSettings365Ads
        Entries = @(
            [PSCustomObject]@{ Hive = 'HKLM'; Path = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableConsumerAccountStateContent'; Value = 1 }
        )
    }
)

try {
    Write-Log -Message '====================================================='
    Write-Log -Message 'Starting Windows privacy settings configuration'
    Write-Log -Message '====================================================='

    $requiresDefaultHive = @($settings | Where-Object { $_.Enabled -and ($_.Entries.Hive -contains 'HKCU') }).Count -gt 0
    $defaultHiveLoaded = $false
    $defaultHiveRoot = "Registry::HKEY_USERS\$DefaultUserMountPoint"

    if ($requiresDefaultHive) {
        if (-not (Test-Path -Path $DefaultUserHive -PathType Leaf)) {
            throw "Default user profile hive was not found at '$DefaultUserHive'."
        }
        if (Test-Path -Path $defaultHiveRoot) {
            throw "Registry mount point 'HKEY_USERS\$DefaultUserMountPoint' is already in use."
        }

        Write-Log -Message "Loading Default user profile hive '$DefaultUserHive' at 'HKU\$DefaultUserMountPoint'"
        $loadOutput = & reg.exe load "HKU\$DefaultUserMountPoint" $DefaultUserHive 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "reg load failed with code ${LASTEXITCODE}: $($loadOutput -join ' ')"
        }
        $defaultHiveLoaded = $true
    }

    try {
        foreach ($setting in $settings) {
            if (-not $setting.Enabled) {
                Write-Log -Message "$($setting.Option): skipped"
                continue
            }

            foreach ($entry in $setting.Entries) {
                $targetPath = if ($entry.Hive -eq 'HKLM') {
                    "HKLM:\$($entry.Path)"
                }
                else {
                    "$defaultHiveRoot\$($entry.Path)"
                }

                if ($null -eq $entry.Value) {
                    Remove-RegistryValue -Path $targetPath -Name $entry.Name
                    Write-Log -Message "Removed $($entry.Hive)\$($entry.Path)\$($entry.Name)"
                }
                else {
                    Set-RegistryDWord -Path $targetPath -Name $entry.Name -Value $entry.Value
                    Write-Log -Message "Set $($entry.Hive)\$($entry.Path)\$($entry.Name) = $($entry.Value)"
                }
            }

            Write-Log -Message "$($setting.Option): applied"
        }
    }
    finally {
        if ($defaultHiveLoaded) {
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            $unloadOutput = & reg.exe unload "HKU\$DefaultUserMountPoint" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log -Message "WARNING: reg unload failed with code ${LASTEXITCODE}: $($unloadOutput -join ' ')" -Type 2
            }
            else {
                Write-Log -Message "Unloaded Default user profile hive from 'HKU\$DefaultUserMountPoint'"
            }
        }
    }

    Write-Log -Message '====================================================='
    Write-Log -Message 'Windows privacy settings configuration completed'
    Write-Log -Message '====================================================='
    Exit-WithCode -ExitCode 0
}
catch {
    Write-Log -Message "ERROR: $($_.Exception.Message)" -Type 3
    Exit-WithCode -ExitCode 1
}
