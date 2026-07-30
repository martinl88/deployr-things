# DeployR Deployment Scripts

This repository is a collection of PowerShell scripts and DeployR content items used to automate Windows deployment tasks with [DeployR](https://2pintsoftware.com/products/deployr), typically run as **Application** content items or task sequence steps.

It includes:

- A custom **task sequence step definition** for installing one or more winget applications (`WinGet/`)
- Standalone **Application** wrappers for software that isn't available in the winget store (VMware Tools, Estonian ID-card software, Dell BIOS Provider)
- Utility scripts for post-deployment configuration, such as setting a laptop's display to its native resolution

Each script/step is self-contained and documented in its own section below.

## Files

- `WinGet/Install-WinGetApps.json` - DeployR step definition for task sequences (import this into DeployR)
- `WinGet/Install-WinGetApps.ps1` - PowerShell script that installs multiple winget apps in a task sequence
- `WinGet/Install-WinGetApp.ps1` - Reusable PowerShell wrapper for DeployR **Application** content items (single app)
- `WinGet/New-DeployRWinGetApp.ps1` - Helper script to create DeployR Application content items for winget packages
- `Install-VMwareTools.ps1` - Reusable PowerShell wrapper that downloads and installs VMware Tools
- `Install-EstonianIDCard.ps1` - Reusable PowerShell wrapper that downloads and installs the Estonian Open-EID ID-card software and the SmartCardRemoval service
- `Install-DellBIOSProvider.ps1` - Reusable PowerShell wrapper that installs the Visual C++ Redistributable (if needed) and the DellBIOSProvider PowerShell module
- `Set-Native-Resolution.ps1` - Legacy script that sets the display to its native resolution using `CIM_VideoControllerResolution` and the legacy `ChangeDisplaySettings` API
- `Set-Native-Resolution-v2.ps1` - Sets the internal laptop panel to its native resolution by reading the EDID via `ChangeDisplaySettingsEx`; replaces `Set-Native-Resolution.ps1`

## Task sequence step definition

1. Create a DeployR content item and upload `WinGet/Install-WinGetApps.ps1` to it.
2. Note the content item ID (GUID) and version, e.g. `d819ff51-72a1-4e3c-bdf3-fcb69cf1bbab:1`.
3. Open `WinGet/Install-WinGetApps.json` and update the `defaultValue` of the hidden `content` option to match your content item ID and version.
4. Import the JSON into DeployR using the DeployR PowerShell module:

```powershell
Import-DeployRStepDefinition -SourceFile "C:\Path\To\WinGet\Install-WinGetApps.json"
```

5. Add the step to a task sequence and enter the desired winget application IDs, one per line, in the `Winget Application IDs` field.

## Application content item wrapper

Use `WinGet/Install-WinGetApp.ps1` to create reusable DeployR **Application** content items for individual winget packages.

1. Create a content item with purpose **Application**.
2. Upload `WinGet/Install-WinGetApp.ps1` to the root of the source files.
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

Use `Install-VMwareTools.ps1` to create a DeployR **Application** content item that downloads and installs the latest VMware Tools. VMware Tools is not available in the winget store, so this wrapper fetches the installer directly from VMware's public package repository.

1. Create a content item with purpose **Application**.
2. Upload `Install-VMwareTools.ps1` to the root of the source files.
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

Use `Install-EstonianIDCard.ps1` to create a DeployR **Application** content item that downloads and installs the Estonian Open-EID ID-card software and the SmartCardRemoval service.

1. Create a content item with purpose **Application**.
2. Upload `Install-EstonianIDCard.ps1` to the root of the source files.
3. Set the installation command line to:

```
pwsh.exe -file .\Install-EstonianIDCard.ps1
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

## Dell BIOS Provider wrapper

Use `Install-DellBIOSProvider.ps1` to create a DeployR **Application** content item that installs the DellBIOSProvider PowerShell module (installing the Visual C++ 2015-2022 Redistributable x64 first, if it isn't already present).

1. Create a content item with purpose **Application**.
2. Upload `Install-DellBIOSProvider.ps1` to the root of the source files.
3. Set the installation command line to:

```
pwsh.exe -file .\Install-DellBIOSProvider.ps1
```

### Notes

- Must run elevated (`#Requires -RunAsAdministrator`).
- Detects an existing VC++ 2015-2022 x64 redistributable via the runtime registry keys and the uninstall registry, then downloads and installs the latest version from `https://aka.ms/vs/17/release/vc_redist.x64.exe` if none is found.
- Registers NuGet as a package provider and trusts PSGallery if needed, then installs (or updates) the `DellBIOSProvider` module for all users.

## Native resolution scripts

- `Set-Native-Resolution-v2.ps1` identifies the internal laptop panel (via WMI `WmiMonitorConnectionParams`/`WmiMonitorRawData`), reads its EDID to determine the true native resolution, and applies it with `ChangeDisplaySettingsEx`. It supports `-WhatIf`, an optional `-DpiScale` parameter, and an `-OptimizeDpi` switch that caps DPI scaling at 125%. This is the preferred script going forward.
- `Set-Native-Resolution.ps1` is the older implementation that infers the native resolution from `CIM_VideoControllerResolution` result ordering and applies it with the legacy `ChangeDisplaySettings` API. It is kept for reference/compatibility but may not reliably pick the correct display in multi-monitor scenarios.

Both scripts must run in an interactive session; changing display resolution from a non-interactive deployment context (e.g. Session 0) will not work.

## Helper script for creating Application content items

Use `WinGet/New-DeployRWinGetApp.ps1` to automate creation of DeployR Application content items for winget packages.

```powershell
.\WinGet\New-DeployRWinGetApp.ps1 -AppName "Mozilla Firefox" -AppID "Mozilla.Firefox" -Connect -Passcode "YOUR_PASSCODE"
```

The helper script:

1. Imports the `DeployR.Utility` module
2. Connects to DeployR if `-Connect` is specified
3. Creates a new Application content item
4. Creates version 1 with the correct installation command line for `Install-WinGetApp.ps1`
5. Uploads `WinGet/Install-WinGetApp.ps1` as the content source
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
- **`-SuccessCodes`** - Comma-separated success codes. Defaults to `0,3010`
- **`-Source`** - Winget source. Defaults to `winget`
- **`-AcceptPackageAgreements`** - Adds `-AcceptPackageAgreements` to the wrapper command line
- **`-AcceptSourceAgreements`** - Adds `-AcceptSourceAgreements` to the wrapper command line
- **`-WrapperScriptPath`** - Path to `Install-WinGetApp.ps1`. Defaults to `.\Install-WinGetApp.ps1` (relative to the `WinGet` folder)
- **`-Connect`** - Call `Connect-DeployR` before creating the item
- **`-Passcode`** - Passcode for `Connect-DeployR`

### Notes

- The script validates that the required DeployR cmdlets exist before making any changes.
- It supports `-WhatIf` so you can preview the actions without creating anything.
- DeployR cmdlet names and parameters can vary between versions. If a command fails, the script reports which step failed so you can adjust parameters to match your module.

## Step options

- **Winget Application IDs** - One or more winget application IDs, separated by newlines, commas, or semicolons. Example: `Mozilla.Firefox`
- **Install Scope** - `machine` or `user`
- **Accept Package Agreements** - Automatically accept package license agreements
- **Accept Source Agreements** - Automatically accept winget source agreements

## Notes

- The script locates `winget.exe` under `C:\Program Files\WindowsApps` automatically.
- Applications are installed one by one in the order they are listed.
- The final exit code is the last non-zero exit code returned by winget, or `0` if all installs succeed.
- If no application IDs are provided, the step exits with code `1`.
