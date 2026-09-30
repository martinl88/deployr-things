#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'InstalledBuiltInApps.json')
)

$ErrorActionPreference = 'Stop'
$catalogSource = 'https://github.com/Raphire/Win11Debloat/blob/32024662f3c602442e7af82bbf52c89143b31aeb/Config/Apps.json'
$catalogCommit = '32024662f3c602442e7af82bbf52c89143b31aeb'
$catalogData = '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'

function Expand-Catalog {
    $compressed = [Convert]::FromBase64String($catalogData)
    $inputStream = [IO.MemoryStream]::new($compressed)
    $gzipStream = [IO.Compression.GZipStream]::new($inputStream, [IO.Compression.CompressionMode]::Decompress)
    $reader = [IO.StreamReader]::new($gzipStream, [Text.Encoding]::UTF8)
    try {
        return $reader.ReadToEnd() | ConvertFrom-Json
    }
    finally {
        $reader.Dispose()
        $gzipStream.Dispose()
        $inputStream.Dispose()
    }
}

function Get-WinGetInventory {
    $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if (-not $command) {
        return [PSCustomObject]@{ Available = $false; Error = 'winget.exe was not found.'; Apps = @() }
    }

    try {
        $output = @(& $command.Source list --accept-source-agreements --disable-interactivity 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "winget list returned exit code $LASTEXITCODE."
        }

        $lines = ($output -join "`n") -split "`r?`n"
        $separatorIndex = -1
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match '^-{3,}') {
                $separatorIndex = $index
                break
            }
        }
        if ($separatorIndex -lt 0) {
            throw 'winget list returned an unrecognized table format.'
        }

        $apps = @(
            for ($index = $separatorIndex + 1; $index -lt $lines.Count; $index++) {
                if ([string]::IsNullOrWhiteSpace($lines[$index])) { continue }
                $fields = [regex]::Split($lines[$index].Trim(), '\s{2,}')
                if ($fields.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($fields[1])) {
                    [PSCustomObject]@{ Name = $fields[0].Trim(); Id = $fields[1].Trim() }
                }
            }
        )
        return [PSCustomObject]@{ Available = $true; Error = $null; Apps = $apps }
    }
    catch {
        return [PSCustomObject]@{ Available = $false; Error = $_.Exception.Message; Apps = @() }
    }
}

$catalog = @(Expand-Catalog)
$installedPackages = @(Get-AppxPackage -AllUsers | Select-Object -ExpandProperty Name -Unique)
$provisionedPackages = @(Get-AppxProvisionedPackage -Online | Select-Object -ExpandProperty DisplayName -Unique)
$wingetInventory = Get-WinGetInventory
$results = [Collections.Generic.List[object]]::new()

foreach ($app in $catalog) {
    $appIds = @($app.AppId)
    $installedMatches = @()
    $provisionedMatches = @()
    $wingetMatches = @()

    if ($app.RemovalMethod -eq 'Appx') {
        foreach ($appId in $appIds) {
            $installedMatches += @($installedPackages | Where-Object { $_ -like "*$appId*" })
            $provisionedMatches += @($provisionedPackages | Where-Object { $_ -like "*$appId*" })
        }
    }
    elseif ($app.RemovalMethod -eq 'WinGet') {
        $wingetMatches = @($wingetInventory.Apps | Where-Object { $appIds -contains $_.Id })
    }

    $installedMatches = @($installedMatches | Sort-Object -Unique)
    $provisionedMatches = @($provisionedMatches | Sort-Object -Unique)
    $wingetMatches = @($wingetMatches | Sort-Object Id -Unique)
    if ($installedMatches.Count -eq 0 -and $provisionedMatches.Count -eq 0 -and $wingetMatches.Count -eq 0) { continue }

    $results.Add([PSCustomObject][ordered]@{
        FriendlyName = $app.FriendlyName
        AppId = $app.AppId
        RemovalMethod = $app.RemovalMethod
        Recommendation = $app.Recommendation
        SelectedByDefault = [bool]$app.SelectedByDefault
        Sources = [PSCustomObject][ordered]@{
            InstalledAppx = $installedMatches
            ProvisionedAppx = $provisionedMatches
            WinGet = @($wingetMatches)
        }
    })
}

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$report = [PSCustomObject][ordered]@{
    CapturedAtUtc = [DateTime]::UtcNow.ToString('o')
    Computer = [PSCustomObject][ordered]@{
        Name = $env:COMPUTERNAME
        WindowsProductName = $os.Caption
        WindowsVersion = $os.Version
        WindowsBuild = $os.BuildNumber
    }
    Catalog = [PSCustomObject][ordered]@{
        Source = $catalogSource
        Commit = $catalogCommit
        EntryCount = $catalog.Count
    }
    WinGet = [PSCustomObject][ordered]@{
        Available = $wingetInventory.Available
        Error = $wingetInventory.Error
    }
    MatchedAppCount = $results.Count
    Apps = @($results | Sort-Object FriendlyName, RemovalMethod)
}

$outputDirectory = Split-Path -Path $OutputPath -Parent
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
$resolvedOutputPath = (Resolve-Path -LiteralPath $OutputPath).Path

Write-Output "Found $($results.Count) installed known removable app(s)."
if (-not $wingetInventory.Available) {
    Write-Warning "WinGet inventory was unavailable: $($wingetInventory.Error)"
}
Write-Output "Report written to: $resolvedOutputPath"
