#Requires -RunAsAdministrator

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-VCRedistInstalled {
    $runtimeKeys = @(
        'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    )

    foreach ($key in $runtimeKeys) {
        if (Test-Path $key) {
            $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
            if ($props.Version -or $props.Installed -eq 1) {
                return $true
            }
        }
    }

    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    $yearPattern = '\b201[5-9]\b|\b202[0-9]\b'
    foreach ($path in $uninstallPaths) {
        if (-not (Test-Path $path)) { continue }
        $items = Get-ChildItem $path -ErrorAction SilentlyContinue |
            Get-ItemProperty -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                $_.DisplayName -match 'Visual C\+\+' -and
                $_.DisplayName -match 'Redistributable' -and
                $_.DisplayName -match 'x64' -and
                $_.DisplayName -match $yearPattern
            }
        if ($items) {
            return $true
        }
    }

    return $false
}

function Install-LatestVCRedist {
    $url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
    $fileName = Split-Path $url -Leaf
    $outFile = Join-Path $env:TEMP $fileName

    Write-Host "Downloading $fileName ..."
    Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing

    Write-Host "Installing $fileName ..."
    $proc = Start-Process -FilePath $outFile -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "Installation of $fileName failed with exit code $($proc.ExitCode)"
    }
}

function Install-DellBIOSProviderModule {
    Write-Host 'Ensuring NuGet package provider is available...'
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }

    Write-Host 'Configuring PSGallery as a trusted repository...'
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

    if (Get-Module -ListAvailable -Name DellBIOSProvider) {
        Write-Host 'DellBIOSProvider found; updating to the latest version...'
        Update-Module -Name DellBIOSProvider -Force
    }
    else {
        Write-Host 'Installing DellBIOSProvider...'
        Install-Module -Name DellBIOSProvider -Scope AllUsers -Force -AllowClobber
    }
}

if (-not (Test-VCRedistInstalled)) {
    Write-Host 'Visual C++ 2015-2022 Redistributable (x64) not found. Installing the latest...'
    Install-LatestVCRedist
}
else {
    Write-Host 'Visual C++ 2015-2022 Redistributable (x64) is already installed.'
}

Install-DellBIOSProviderModule

Write-Host 'Done.'
