# DeployR Deployment Scripts

This repository is a collection of PowerShell scripts and DeployR content items used to automate Windows deployment tasks with [DeployR](https://2pintsoftware.com/products/deployr), typically run as **Application** content items or task sequence steps.

It includes:

- A custom **task sequence step definition** for installing one or more winget applications (`App - Install Winget Applications-*/`)
- Standalone **Application** wrappers for software that isn't available in the winget store (VMware Tools and Estonian ID-card software)
- Utility task sequence steps for post-deployment configuration, such as configuring Dell BIOS settings, configuring Windows power settings, and toggling audio

Each script/step is self-contained and documented in its own section below.

## Files

- `App - Install Winget Applications-*/` - DeployR step definition for task sequences (import this into DeployR)
- `App - Install Winget Applications-*/ReferencedContent/WinGetAppsScripts-*/` - Importable DeployR content item bundle containing the multi-app script
- `App - Install Winget Applications-*/Install-WinGetApp.ps1` - Reusable PowerShell wrapper for DeployR **Application** content items (single app)
- `App - Install Winget Applications-*/New-DeployRWinGetApp.ps1` - Helper script to create DeployR Application content items for winget packages
- `App - VMware Tools-*/` - Importable DeployR Application content item bundle containing the VMware Tools script
- `App - Estonian ID-Card-*/` - Importable DeployR Application content item bundle containing the Estonian ID-Card script
- `Customize - Configure Windows Power Settings-*/` - DeployR step definition for configuring Windows power settings in a task sequence
- `Customize - Configure Windows Power Settings-*/ReferencedContent/PowerSettingsScripts-*/` - Importable DeployR content item bundle containing the power settings script
- `Customize - Toggle Audio-*/` - DeployR step definition for toggling audio mute in a task sequence
- `Customize - Toggle Audio-*/ReferencedContent/ToggleAudioScripts-*/` - Importable DeployR content item bundle containing the audio script
- `Customize - Configure ODBC System DSN-*/` - DeployR step definition for creating a system-wide ODBC DSN in a task sequence
- `Customize - Configure ODBC System DSN-*/ReferencedContent/ODBCDsnScripts-*/` - Importable DeployR content item bundle containing the ODBC DSN script
- `Customize - Privacy Settings-*/` - DeployR step definition for applying Windows privacy and suggested-content settings in a task sequence
- `Customize - Privacy Settings-*/ReferencedContent/PrivacyScripts-*/` - Importable DeployR content item bundle containing the privacy settings script
- `Dell - Change BIOS Settings-*/` - DeployR step definition for configuring Dell BIOS settings in a task sequence
- `Dell - Change BIOS Settings-*/ReferencedContent/DellBIOSSettingsScripts-*/` - Importable DeployR content item bundle containing the Dell BIOS settings script and CSV
- `Manage-InstallWim.ps1` - Interactive utility for cataloging WIM editions and exporting selected editions as individual WIM files
- `Customize - Remove Windows Built-in Applications-*/` - DeployR step definition with per-app checkboxes for removing built-in applications
- `Customize - Remove Windows Built-in Applications-*/ReferencedContent/BuiltInAppRemovalScripts-*/` - Importable content item containing the removal script
- `Customize - Remove Windows Built-in Applications-*/Get-InstalledBuiltInApps.ps1` - Offline helper that reports installed apps found in an embedded Win11Debloat catalog snapshot
- `Customize - Install Fonts-*/` - DeployR step definition for installing Windows fonts in a task sequence
- `Customize - Install Fonts-*/ReferencedContent/FontInstallScripts-*/` - Importable content item containing the font install script
- `Customize - Install Fonts-*/ReferencedContent/Fonts-*/` - Importable content item to hold the font files installed by the step
- `Import-DeployRItems.ps1` - Interactive helper that imports or updates all DeployR content items and step definitions found in the repository

## Manage install.wim editions

Run `Manage-InstallWim.ps1` in Windows PowerShell to catalog the editions in an `install.wim`, select one or more editions in `Out-GridView`, and export each selection as a separate single-index WIM:

```powershell
.\Manage-InstallWim.ps1
```

By default, the script reads `install.wim` beside the script and writes exports to an `Editions` folder beside the source WIM. Use parameters to choose other locations:

```powershell
.\Manage-InstallWim.ps1 -ImagePath D:\sources\install.wim -OutputPath E:\WindowsEditions
```

Export names combine useful image metadata, for example `Windows 11 Pro 24H2 (10.0.26100.1) x64 en-US.wim`. Marketing release labels are inferred only for known Windows builds; unknown builds retain their full version. Existing files with generated names are overwritten, while unrelated files in the output folder are left untouched. The script requires the Windows DISM PowerShell commands and `Out-GridView`.

After successful exports, the script asks whether to import the WIMs into DeployR. Use `-ImportToDeployR` to import without prompting:

```powershell
.\Manage-InstallWim.ps1 -ImagePath D:\sources\install.wim -ImportToDeployR
```

Run the script from an elevated Windows PowerShell session. The caller must already be connected to DeployR. Each WIM is uploaded as an **Operating System** purpose, **Single File** content item whose name starts with `OS - `, with a generated description and Windows/release/architecture/language tags. If an item with the generated name already exists, the script adds and uploads a new version instead of creating a duplicate item. A failed upload is reported but does not delete the item or version that was created.

## Reference-image built-in app inventory

Run `Customize - Remove Windows Built-in Applications-*/Get-InstalledBuiltInApps.ps1` from an elevated Windows PowerShell session on the reference image:

```powershell
.\Customize - Remove Windows Built-in Applications-7e3611fe-5752-412e-a107-6198cdd1a7e5\Get-InstalledBuiltInApps.ps1
```

The helper inventories Appx packages installed for any user, provisioned Appx packages, and known WinGet packages. It only reports entries from its embedded Win11Debloat catalog snapshot and does not remove anything. The default report is `InstalledBuiltInApps.json` beside the script; use `-OutputPath` to choose another location:

```powershell
.\Customize - Remove Windows Built-in Applications-7e3611fe-5752-412e-a107-6198cdd1a7e5\Get-InstalledBuiltInApps.ps1 -OutputPath C:\Temp\InstalledBuiltInApps.json
```

Provide the generated JSON report to select and lock down the app list for the DeployR removal step definition.

## Remove Windows built-in applications

The `Customize - Remove Windows Built-in Applications-*` step exposes all 38 applications detected on the reference image as individual checkboxes. The 14 applications selected by default by Win11Debloat are checked by default; optional and unsafe applications are available but unchecked. Unsafe options are marked in their display names.

1. Import the bundled content item:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\Customize - Remove Windows Built-in Applications-7e3611fe-5752-412e-a107-6198cdd1a7e5\ReferencedContent\BuiltInAppRemovalScripts-48c6d739-535b-4b75-8be6-d86d55a1cd59\48c6d739-535b-4b75-8be6-d86d55a1cd59.json"
```

2. Import the step definition:

```powershell
Import-DeployRStepDefinition -SourceFile "C:\Path\To\Customize - Remove Windows Built-in Applications-7e3611fe-5752-412e-a107-6198cdd1a7e5\7e3611fe-5752-412e-a107-6198cdd1a7e5.json"
```

3. Add the step to a task sequence and review the 38 removal checkboxes before deployment.

The step removes selected Appx packages for all existing users and removes their online provisioned packages so they are not installed for new users. OneDrive and Edge use WinGet instead. Every selected application is checked after removal; any remaining package fails the step. Results are written in CMTrace format to `C:\_2P\Logs\BuiltInAppRemoval.log`.

### Start menu cleanup

Use the **Start menu cleanup** drop-down to control what happens after app removal:

- **Both** (default) - Disables consumer app suggestions / cloud-optimized content in `HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent`, and clears the Start menu `TempState`/`LocalState` cache for the default user profile so new users do not inherit stale tiles.
- **Registry only** - Only sets the `CloudContent` policies.
- **Cache only** - Only clears the default user Start menu cache.
- **No cleanup** - Leaves Start menu settings untouched.

This helps prevent ghost tiles or suggested-app placeholders from appearing after the package is removed. Existing user profiles are not modified.

## Install fonts

The `Customize - Install Fonts-*` step installs every font file in a font-files content item. Two content items are used: one holds the install script, the other holds the fonts.

1. Place the `.fon`, `.fnt`, `.ttf`, `.ttc`, or `.otf` files to install in `Customize - Install Fonts-*/ReferencedContent/Fonts-*/c83bb5aa-dc00-4753-aaad-12204fc80f26/1/`.

2. Import the font-files and script content items, then the step definition (or run `Import-DeployRItems.ps1` and select all three):

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\Customize - Install Fonts-28e96612-f57d-4a6e-8fb8-58cbce06b1af\ReferencedContent\Fonts-c83bb5aa-dc00-4753-aaad-12204fc80f26\c83bb5aa-dc00-4753-aaad-12204fc80f26.json"
Import-DeployRContentItem -SourceFile "C:\Path\To\Customize - Install Fonts-28e96612-f57d-4a6e-8fb8-58cbce06b1af\ReferencedContent\FontInstallScripts-0e085087-afd9-4a6c-9f80-184e0699878e\0e085087-afd9-4a6c-9f80-184e0699878e.json"
Import-DeployRStepDefinition -SourceFile "C:\Path\To\Customize - Install Fonts-28e96612-f57d-4a6e-8fb8-58cbce06b1af\28e96612-f57d-4a6e-8fb8-58cbce06b1af.json"
```

3. Add the step to a task sequence. The **Font files** option defaults to the bundled `Fonts` content item; select a different content item to install another set of fonts. Enable **Include subfolders** to pick up fonts nested in the content item.

Each font is copied to the Windows Fonts folder, registered with GDI, and given a `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` registry value so it persists across sessions. Results are written in CMTrace format to `C:\_2P\Logs\FontInstall.log`. The step fails if no font files are found or any font fails to install.

## Task sequence step definition

1. Import the bundled content item first:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\App - Install Winget Applications-856fcb58-88f4-483e-bb36-36d5ab4e9dc4\ReferencedContent\WinGetAppsScripts-2d14c72e-1069-40ae-a8d7-14161c0f66f1\2d14c72e-1069-40ae-a8d7-14161c0f66f1.json"
```

2. Import the step definition:

```powershell
Import-DeployRStepDefinition -SourceFile "C:\Path\To\App - Install Winget Applications-856fcb58-88f4-483e-bb36-36d5ab4e9dc4\856fcb58-88f4-483e-bb36-36d5ab4e9dc4.json"
```

3. Add the step to a task sequence and enter the desired winget application IDs, one per line, in the `Winget Application IDs` field.

The step definition already references content item version `2d14c72e-1069-40ae-a8d7-14161c0f66f1:1`. Keep the JSON file and its sibling `2d14c72e-1069-40ae-a8d7-14161c0f66f1\1` source folder together when importing.

### Step options

- **Winget Application IDs** - One or more winget application IDs, separated by newlines, commas, or semicolons. Example: `Mozilla.Firefox`
- **Install Scope** - `machine` or `user`
- **Accept Package Agreements** - Automatically accept package license agreements
- **Accept Source Agreements** - Automatically accept winget source agreements

### Notes

- The script locates `winget.exe` under `C:\Program Files\WindowsApps` automatically.
- Applications are installed one by one in the order they are listed.
- The final exit code is the last non-zero exit code returned by winget, or `0` if all installs succeed.
- If no application IDs are provided, the step exits with code `1`.

## Application content item wrapper

Use `App - Install Winget Applications-*/Install-WinGetApp.ps1` to create reusable DeployR **Application** content items for individual winget packages.

1. Create a content item with purpose **Application**.
2. Upload `App - Install Winget Applications-*/Install-WinGetApp.ps1` to the root of the source files.
3. Set the installation command line to:

```
pwsh.exe -file .\Install-WinGetApp.ps1 -AppID "Mozilla.Firefox" -AcceptPackageAgreements -AcceptSourceAgreements
```

### Available parameters

- **`-AppID`** (required) - The winget application ID, e.g. `Mozilla.Firefox`
- **`-Scope`** - `machine` (default) or `user`
- **`-AcceptPackageAgreements`** - Add `--accept-package-agreements`
- **`-AcceptSourceAgreements`** - Add `--accept-source-agreements`
- **`-Silent`** - Run winget silently. Defaults to `$true`; disable with `-Silent:$false`
- **`-Source`** - Winget source. Defaults to `winget`
- **`-LogFile`** - Path to the log file. Defaults to `C:\windows\Temp\WinGetApp_Install.log`

## VMware Tools wrapper

Use `App - VMware Tools-*/6fd76f0f-43ee-4b44-b496-2c0c61fdb471/1/Install-VMwareTools.ps1` to create a DeployR **Application** content item that downloads and installs the latest VMware Tools. VMware Tools is not available in the winget store, so this wrapper fetches the installer directly from VMware's public package repository.

Import the ready-made content item:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\App - VMware Tools-6fd76f0f-43ee-4b44-b496-2c0c61fdb471\6fd76f0f-43ee-4b44-b496-2c0c61fdb471.json"
```

Or create the content item manually:

1. Create a content item with purpose **Application**.
2. Upload `App - VMware Tools-*/6fd76f0f-43ee-4b44-b496-2c0c61fdb471/1/Install-VMwareTools.ps1` to the root of the source files.
3. Set the installation command line to:

```
pwsh.exe -file .\Install-VMwareTools.ps1
```

### Available parameters

- **`-DownloadUrl`** - URL to the VMware Tools directory listing. Defaults to `https://packages.vmware.com/tools/esx/latest/windows/x64/`
- **`-InstallArgs`** - Silent install arguments. Defaults to `/S /v"/qn REBOOT=R ADDLOCAL=ALL"`
- **`-Timeout`** - Download and install timeout in seconds. Defaults to `1800`
- **`-LogFile`** - Path to the log file. Defaults to `C:\windows\Temp\VMwareTools_Install.log`

### Notes

- The script parses the directory listing at the `-DownloadUrl` to find the latest `VMware-tools-<version>-<build>-x64.exe`.
- If the listing format changes, you can override `-DownloadUrl` with a direct URL to a specific `.exe` file.
- The default install arguments suppress reboot (`REBOOT=R`) and install all components (`ADDLOCAL=ALL`).

## Estonian ID-Card wrapper

Use `App - Estonian ID-Card-*/8e762d0f-4345-45d8-8d30-db114cbc20fe/1/Install-EstonianIDCard.ps1` to create a DeployR **Application** content item that downloads and installs the Estonian Open-EID ID-card software and the SmartCardRemoval service.

Import the ready-made content item:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\App - Estonian ID-Card-8e762d0f-4345-45d8-8d30-db114cbc20fe\8e762d0f-4345-45d8-8d30-db114cbc20fe.json"
```

Or create the content item manually:

1. Create a content item with purpose **Application**.
2. Upload `App - Estonian ID-Card-*/8e762d0f-4345-45d8-8d30-db114cbc20fe/1/Install-EstonianIDCard.ps1` to the root of the source files.
3. Set the installation command line to:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-EstonianIDCard.ps1
```

### Available parameters

- **`-LogFile`** - Path to the log file. Defaults to `C:\windows\Temp\EstonianIDCard_Install.log`
- **`-OpenEIDUrl`** - Open-EID installer page or a direct `.exe` URL. Defaults to `https://www.id.ee/artikkel/paigalda-id-tarkvara/`
- **`-OpenEIDArgs`** - Silent install arguments for Open-EID. Defaults to `/passive /quiet /norestart IconsDesktop=0 RunQesteidutil=0`
- **`-SmartCardRepo`** - GitHub repository for SmartCardRemoval. Defaults to `open-eid/smart-card-removal`
- **`-Timeout`** - Download and install timeout in seconds. Defaults to `1800`

### Notes

- The script discovers the Open-EID installer by scraping the `-OpenEIDUrl` page for a link whose `href` ends in `.exe` and whose `outerHTML` contains `Open-EID`.
- If the page format changes, you can point `-OpenEIDUrl` at a direct `.exe` URL.
- The script queries the GitHub Releases API for the latest SmartCardRemoval MSI and includes a `User-Agent` header.
- Open-EID and SmartCardRemoval are installed sequentially because SmartCardRemoval depends on the ID-card middleware being present.
- The script returns exit code `0` if at least one component installs successfully. It returns the last non-zero exit code only if both components fail.

## Configure Dell BIOS settings

Use `Dell - Change BIOS Settings-*/ReferencedContent/DellBIOSSettingsScripts-*/c163d154-dc67-44a9-a159-bd27cc2e757f/1/Set-DellBIOSSettings.ps1` as a DeployR **task sequence step** to configure common Dell BIOS settings and optionally set or clear the BIOS admin and system passwords.

1. Make sure the `DellBIOSProvider` PowerShell module is installed on the target system first.

2. Import the bundled content item first:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\Dell - Change BIOS Settings-0d583c5d-1b66-4af4-8491-ff9d170d9856\ReferencedContent\DellBIOSSettingsScripts-c163d154-dc67-44a9-a159-bd27cc2e757f\c163d154-dc67-44a9-a159-bd27cc2e757f.json"
```

3. Import the step definition:

```powershell
Import-DeployRStepDefinition -SourceFile "C:\Path\To\Dell - Change BIOS Settings-0d583c5d-1b66-4af4-8491-ff9d170d9856\0d583c5d-1b66-4af4-8491-ff9d170d9856.json"
```

4. Add the step to a task sequence. Each BIOS setting is presented as a drop-down (combo box) populated with the possible values from `DellBiosSettings.csv`, so only supported values can be selected.

The step definition already references content item version `c163d154-dc67-44a9-a159-bd27cc2e757f:1`. Keep the JSON file and its sibling `c163d154-dc67-44a9-a159-bd27cc2e757f\1` source folder together when importing.

### Available options

- **`BIOS Admin Password`** (required) - The current BIOS admin password. Also used to set or clear the admin password.
- **`Clear Admin Password`** - When enabled, the script applies the BIOS settings and then clears the admin password. Requires the `BIOS Admin Password` field.
- **`BIOS System Password`** - The BIOS system (user) password. Used to set the system password if one does not exist, or to clear it when `Clear System Password` is enabled and the admin password is not available.
- **`Clear System Password`** - When enabled, the script clears the system password after applying settings. Requires either the `BIOS System Password` or `BIOS Admin Password` field.
- **BIOS settings drop-downs** - `Keyboard Illumination`, `USB PowerShare`, `Absolute`, `Primary Battery Charge Configuration`, `Fn Lock`, `Fn Lock Mode`, `WLAN Auto Sense`, `Wake On AC`, `Wake On LAN`, and `NumLock`. Each drop-down uses the possible values from `DellBiosSettings.csv`.

### Notes

- Must run elevated (`#Requires -RunAsAdministrator`).
- The script exits with `0` and skips on non-Dell systems unless `-FailOnNonDell` is passed.
- The script reads `DellBiosSettings.csv` at runtime. If the CSV is missing, it falls back to built-in paths and possible values.
- Default settings: `KeyboardIllumination` = `Bright`, `UsbPowerShare` = `Enabled`, `Absolute` = `DisableAbsolute`, `PrimaryBattChargeCfg` = `PrimAcUse`, `FnLock` = `Enabled`, `FnLockMode` = `EnableSecondary`, `WlanAutoSense` = `Enabled`, `WakeOnAc` = `Disabled`, `WakeOnLan` = `LanOnly`, `NumLock` = `Enabled`.
- Settings that are not exposed by a particular model are skipped.
- The password is passed in plain text through the step definition; ensure the task sequence and content item are restricted to authorized administrators.

## Configure Windows power settings

Use `Customize - Configure Windows Power Settings-*/ReferencedContent/PowerSettingsScripts-*/7ce6e61b-4006-42c6-8386-4b6091c842ef/1/Set-PowerSettings.ps1` as a DeployR **task sequence step** to configure and activate the Windows Balanced power plan with separate values for plugged-in and battery operation.

1. Import the bundled content item first:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\Customize - Configure Windows Power Settings-6f9badd5-84bd-4f6d-b741-01edf050f09a\ReferencedContent\PowerSettingsScripts-7ce6e61b-4006-42c6-8386-4b6091c842ef\7ce6e61b-4006-42c6-8386-4b6091c842ef.json"
```

2. Import the step definition:

```powershell
Import-DeployRStepDefinition -SourceFile "C:\Path\To\Customize - Configure Windows Power Settings-6f9badd5-84bd-4f6d-b741-01edf050f09a\6f9badd5-84bd-4f6d-b741-01edf050f09a.json"
```

3. Add the step to a task sequence and populate only the settings that the step should manage.

The step definition already references content item version `7ce6e61b-4006-42c6-8386-4b6091c842ef:1`. Keep the JSON file and its sibling `7ce6e61b-4006-42c6-8386-4b6091c842ef\1` source folder together when importing.

### Available options

- **Display timeout** - Separate plugged-in and battery values in whole minutes.
- **Sleep timeout** - Separate plugged-in and battery values in whole minutes.
- **Hibernate timeout** - Separate plugged-in and battery values in whole minutes.
- **Lid close action** - `No change`, `Do nothing`, `Sleep`, `Hibernate`, or `Shut down`, independently for plugged-in and battery operation.
- **Power button action** - The same action choices, independently for plugged-in and battery operation.
- **Sleep button action** - The same action choices, independently for plugged-in and battery operation.
- **System hibernation** - `No change`, `Enabled`, or `Disabled` for the system-wide Windows hibernation feature.
- **Fast startup** - `No change`, `Enabled`, or `Disabled`. Enabling Fast startup automatically enables hibernation because Windows requires it.

### Notes

- Must run elevated (`#Requires -RunAsAdministrator`).
- Blank timeout fields and `No change` drop-down values preserve the existing setting.
- Timeout values are minutes; `0` means Never.
- The step always activates the Windows Balanced power plan (`SCHEME_BALANCED`) and applies any requested settings to it.
- System hibernation and Fast startup are machine-wide settings rather than per-plan settings. The script rejects disabling hibernation while also requesting a hibernate timeout, Hibernate action, or enabled Fast startup.
- Fast startup is configured through `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power\HiberbootEnabled` and the applied value is verified.
- Some computers do not expose a lid or sleep button. Unsupported `powercfg` settings are reported as failures in `C:\_2P\Logs\PowerSettings.log`.

## Configure Windows privacy settings

Use `Customize - Privacy Settings-*/ReferencedContent/PrivacyScripts-*/36437104-9d9e-46ff-b555-b698f4add97e/1/Set-PrivacySettings.ps1` as a DeployR **task sequence step** to apply Windows privacy and suggested-content settings, based on the tweaks used by [Win11Debloat](https://github.com/raphire/win11debloat).

1. Import the bundled content item first:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\Customize - Privacy Settings-89ec4b4d-4391-4a1a-aca7-8d1c19e7e753\ReferencedContent\PrivacyScripts-36437104-9d9e-46ff-b555-b698f4add97e\36437104-9d9e-46ff-b555-b698f4add97e.json"
```

2. Import the step definition:

```powershell
Import-DeployRStepDefinition -SourceFile "C:\Path\To\Customize - Privacy Settings-89ec4b4d-4391-4a1a-aca7-8d1c19e7e753\89ec4b4d-4391-4a1a-aca7-8d1c19e7e753.json"
```

3. Add the step to a task sequence and check only the settings that the step should apply. Unchecked options leave the system unchanged.

The step definition already references content item version `36437104-9d9e-46ff-b555-b698f4add97e:1`. Keep the JSON file and its sibling `36437104-9d9e-46ff-b555-b698f4add97e\1` source folder together when importing.

### Available options

- **Disable telemetry, tracking & targeted ads** - Advertising ID, tailored experiences, online speech recognition, inking/typing personalization, diagnostic data (`AllowTelemetry`), activity history, app-launch tracking, feedback prompts, and Edge personalization/diagnostic reporting.
- **Disable tips, tricks & suggested content throughout Windows** - Windows welcome experience, Start suggestions and recommendations, tips while using Windows, suggested Settings content, account and sync provider notifications, silent suggested-app installs, Phone Link suggestions, and backup reminder notifications.
- **Disable Windows location services & app location access** - System-wide location services via the `LocationAndSensors` policy.
- **Disable Find My Device location tracking** - Via the `FindMyDevice` policy.
- **Disable tips & tricks on the lock screen** - Fun facts, tips, and rotating overlay content on the lock screen.
- **Disable Windows Spotlight for desktop** - Spotlight wallpaper collection and the "Learn about this picture" desktop icon.
- **Disable ads, suggestions and newsfeed in Edge** - New tab page MSN feed and sponsored content, shopping assistant, tab services, alternate error pages, feedback prompts, recommendations, wallet donation prompts, and default-browser campaigns.
- **Hide Microsoft 365 Copilot ads in Settings Home** - Via the `DisableConsumerAccountStateContent` policy.

### Notes

- Must run elevated (`#Requires -RunAsAdministrator`).
- HKLM policy values are written directly. Because task sequence steps run as SYSTEM, HKCU values are applied to the **Default user profile** hive (`C:\Users\Default\NTUSER.DAT`, mounted temporarily at `HKU\DeployRPrivacyDefault`) so all new user profiles inherit them. Existing user profiles are not modified.
- Every written value is read back and verified; a mismatch fails the step.
- `AllowTelemetry=0` is fully honored only on Enterprise/Education SKUs (same caveat as Win11Debloat); it is harmless elsewhere.
- Applied settings and skipped options are logged to `C:\_2P\Logs\PrivacySettings.log` in CMTrace format.

## Configure ODBC system DSN

Use `New-ODBCSystemDsn.ps1` (in the referenced content item under `Customize - Configure ODBC System DSN-*/ReferencedContent/`) as a DeployR **task sequence step** to create or update a system-wide ODBC data source name in the 64-bit and/or 32-bit ODBC registry hives. Each step instance creates a single DSN; add the step multiple times for multiple DSNs.

1. Import the bundled content item first:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\Customize - Configure ODBC System DSN-657f926b-5a09-4549-b79b-3d1a63c9a7b2\ReferencedContent\ODBCDsnScripts-82dda356-c7ca-4448-a476-0806d62a0242\82dda356-c7ca-4448-a476-0806d62a0242.json"
```

2. Import the step definition:

```powershell
Import-DeployRStepDefinition -SourceFile "C:\Path\To\Customize - Configure ODBC System DSN-657f926b-5a09-4549-b79b-3d1a63c9a7b2\657f926b-5a09-4549-b79b-3d1a63c9a7b2.json"
```

3. Add the step to a task sequence and fill in the DSN details.

The step definition already references content item version `82dda356-c7ca-4448-a476-0806d62a0242:1`. Keep the JSON file and its sibling `82dda356-c7ca-4448-a476-0806d62a0242\1` source folder together when importing.

### Available options

- **DSN Name** (required) - Name of the system DSN to create or update.
- **DSN Description** - Optional description stored in the DSN.
- **ODBC Driver** (required) - `ODBC Driver 18 for SQL Server` (default), `ODBC Driver 17 for SQL Server`, `SQL Server`, `SQL Server Native Client 11.0`, `MySQL ODBC 8.0 Unicode Driver`, `PostgreSQL Unicode`, or `Other`.
- **Other Driver Name** - Driver name used when `ODBC Driver` is `Other`. Must match the `ODBCINST.INI` entry exactly.
- **Server** - Server name or address stored in the DSN.
- **Database** - Default database stored in the DSN.
- **Username** - SQL login username. Stored as the `UID` attribute in the DSN. Optional; only used when **Trusted Connection** is `No`.
- **Password** - SQL login password. Stored as the `PWD` attribute in the DSN. Optional; only used when **Trusted Connection** is `No`.
- **Trusted Connection** - `No` (default) or `Yes`; sets `Trusted_Connection=Yes` for integrated authentication.
- **Architecture** - `Both` (default), `64-bit only`, or `32-bit only`. 64-bit writes to `HKLM:\SOFTWARE\ODBC`, 32-bit writes to the WOW6432Node hive.
- **Additional Attributes** - Extra DSN attributes, one `key=value` per line. Example: `Encrypt=Yes`. `UID` and `PWD` set via **Username** / **Password** take precedence over values supplied here.

### Notes

- Must run elevated (`#Requires -RunAsAdministrator`).
- The specified ODBC driver must already be installed for each requested architecture; the step fails if the driver is missing from `ODBCINST.INI`.
- If the DSN already exists its values are updated in place.
- Username and password values are passed in plain text through the task sequence and stored in the registry DSN. Restrict the task sequence and content item to authorized administrators.
- Logs to `C:\_2P\Logs\ODBCDsn.log` in CMTrace format. Exits `0` on success, `1` on failure.

## Toggle audio

Use `Toggle-Audio.ps1` (in the referenced content item under `Customize - Toggle Audio-*/ReferencedContent/`) to control the master mute state of the default audio playback device via the Windows Core Audio `IAudioEndpointVolume` interface. No external dependencies.

```powershell
.\Toggle-Audio.ps1                     # toggle mute state
.\Toggle-Audio.ps1 -Mute               # mute
.\Toggle-Audio.ps1 -Unmute             # unmute
.\Toggle-Audio.ps1 -Behaviour Unmute   # unmute (alternative to the switches)
```

It is also available as a DeployR **task sequence step**:

1. Import the bundled content item first:

```powershell
Import-DeployRContentItem -SourceFile "C:\Path\To\Customize - Toggle Audio-26787cc1-e72a-4387-b277-619f1f1f4b5d\ReferencedContent\ToggleAudioScripts-433116f0-6e39-4b1b-b78f-c556a72ed573\433116f0-6e39-4b1b-b78f-c556a72ed573.json"
```

2. Import the step definition:

```powershell
Import-DeployRStepDefinition -SourceFile "C:\Path\To\Customize - Toggle Audio-26787cc1-e72a-4387-b277-619f1f1f4b5d\26787cc1-e72a-4387-b277-619f1f1f4b5d.json"
```

3. Add the step to a task sequence and select the desired behaviour.

The step definition already references content item version `433116f0-6e39-4b1b-b78f-c556a72ed573:1`. Keep the JSON file and its sibling `433116f0-6e39-4b1b-b78f-c556a72ed573\1` source folder together when importing.

### Available options

- **Behaviour** - `Toggle` (default; flips the current mute state), `Mute`, or `Unmute`.

### Notes

- Does not require elevation; affects the default render endpoint of the calling session.
- Must run in an interactive session; there is no audio endpoint in Session 0.
- If no audio playback device is present (e.g. Session 0 or a machine without audio hardware), the script logs a message and exits `0` so the step is skipped rather than failing.
- Exits `0` on success, `1` on failure (e.g. both `-Mute` and `-Unmute` specified).
- To skip the step entirely in a task sequence, add a **PowerShell condition** on the step in the task sequence editor that returns `$true` only when an audio device exists, for example:

```powershell
return [bool](Get-PnpDevice -Class 'AudioEndpoint','Media' -Status 'OK' -ErrorAction SilentlyContinue)
```

## Helper script for creating Application content items

Use `App - Install Winget Applications-*/New-DeployRWinGetApp.ps1` to automate creation of DeployR Application content items for winget packages.

```powershell
.\App - Install Winget Applications-856fcb58-88f4-483e-bb36-36d5ab4e9dc4\New-DeployRWinGetApp.ps1 -AppName "Mozilla Firefox" -AppID "Mozilla.Firefox" -Connect -Passcode "YOUR_PASSCODE"
```

The helper script:

1. Imports the `DeployR.Utility` module
2. Connects to DeployR if `-Connect` is specified
3. Creates a new Application content item
4. Creates version 1 with the correct installation command line for `Install-WinGetApp.ps1`
5. Uploads `App - Install Winget Applications-*/Install-WinGetApp.ps1` as the content source
6. Adds the `winget` tag (and any additional tags you specify)

### Parameters

- **`-AppName`** (required) - Display name for the new content item
- **`-AppID`** (required) - Winget application ID
- **`-Purpose`** - Content item purpose. Defaults to `Application`
- **`-Type`** - Content item type. Defaults to `SingleFile`
- **`-Tags`** - Array of tags. Defaults to `winget`
- **`-Description`** - Optional description
- **`-Status`** - Version status. Defaults to `Active`
- **`-Scope`** - `machine` (default) or `user`
- **`-SuccessCodes`** - Space-separated success codes. Defaults to `0 3010`
- **`-Source`** - Winget source. Defaults to `winget`
- **`-AcceptPackageAgreements`** - Adds `-AcceptPackageAgreements` to the wrapper command line
- **`-AcceptSourceAgreements`** - Adds `-AcceptSourceAgreements` to the wrapper command line
- **`-WrapperScriptPath`** - Path to `Install-WinGetApp.ps1`. Defaults to `.\Install-WinGetApp.ps1` (relative to the script's folder)
- **`-Connect`** - Call `Connect-DeployR` before creating the item
- **`-Passcode`** - Passcode for `Connect-DeployR`

### Notes

- The script validates that the required DeployR cmdlets exist before making any changes.
- It supports `-WhatIf` so you can preview the actions without creating anything.
- DeployR cmdlet names and parameters can vary between versions. If a command fails, the script reports which step failed so you can adjust parameters to match your module.

## Import all DeployR items

Use `Import-DeployRItems.ps1` to discover all DeployR content items and step definitions in this repository and import or update them interactively.

```powershell
.\Import-DeployRItems.ps1
```

The script scans the repository for `.json` files that define DeployR content items or step definitions, presents them in `Out-GridView`, and imports the selected items in the correct order (content items first, then step definitions). If a content item already exists on the server, its source files are updated to match the local versions.

### Requirements

- PowerShell 7.0 or later
- `Out-GridView` (for example, the `Microsoft.PowerShell.GraphicalTools` module on PowerShell 7)
- The `DeployR.Utility` module installed at `C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility`, or available via `Import-Module`


