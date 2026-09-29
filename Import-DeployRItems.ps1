#Requires -Version 7.0

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = $PSScriptRoot
$deployRModulePath = "C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility"
$deployRCommands = @(
    "Import-DeployRContentItem"
    "Import-DeployRStepDefinition"
    "Update-DeployRContentItemContent"
    "Get-DeployRContentItem"
)

function Get-DeployRRepositoryItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    foreach ($file in Get-ChildItem -LiteralPath $Path -Filter "*.json" -File -Recurse) {
        try {
            $definition = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "Skipping invalid JSON '$($file.FullName)': $($_.Exception.Message)"
            continue
        }

        $itemType = if ($definition.contentItemType -and $definition.contentItemPurpose) {
            "Content Item"
        }
        elseif ($definition.typeName -and $definition.versions.stepDefinitionId) {
            "Step Definition"
        }
        else {
            continue
        }

        $versions = @($definition.versions | ForEach-Object { $_.versionNo })
        [PSCustomObject]@{
            Type         = $itemType
            Name         = [string]$definition.name
            Id           = [string]$definition.id
            Versions     = $versions -join ", "
            RelativePath = [System.IO.Path]::GetRelativePath($Path, $file.FullName)
            SourceFile   = $file.FullName
            Definition   = $definition
        }
    }
}

function Import-DeployRPrerequisites {
    if (-not (Get-Command -Name "Out-GridView" -ErrorAction SilentlyContinue)) {
        throw "Out-GridView is not available. Install a PowerShell 7 module that provides Out-GridView, such as Microsoft.PowerShell.GraphicalTools."
    }

    $missingCommands = @($deployRCommands | Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) })
    if ($missingCommands.Count -eq 0) {
        return
    }

    try {
        Import-Module "DeployR.Utility" -ErrorAction Stop
    }
    catch {
        if (-not (Test-Path -LiteralPath $deployRModulePath)) {
            throw "DeployR.Utility could not be imported and was not found at '$deployRModulePath'."
        }
        Import-Module $deployRModulePath -ErrorAction Stop
    }

    $missingCommands = @($deployRCommands | Where-Object { -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) })
    if ($missingCommands.Count -gt 0) {
        throw "Required command(s) not found after importing DeployR.Utility: $($missingCommands -join ', ')."
    }
}

Import-DeployRPrerequisites

$items = @(Get-DeployRRepositoryItem -Path $repositoryRoot | Sort-Object Type, Name, RelativePath)
if ($items.Count -eq 0) {
    Write-Warning "No DeployR step definitions or content items were found under '$repositoryRoot'."
    return
}

$selection = @(
    $items |
        Select-Object Type, Name, Id, Versions, RelativePath |
        Out-GridView -Title "Select DeployR items to install or update (Ctrl/Shift for multiple)" -PassThru
)

if ($selection.Count -eq 0) {
    Write-Host "No items selected. No changes were made."
    return
}

$selectedPaths = @($selection.RelativePath)
$results = [System.Collections.Generic.List[object]]::new()
$orderedSelection = @(
    $items |
        Where-Object { $_.RelativePath -in $selectedPaths } |
        Sort-Object @{ Expression = { if ($_.Type -eq "Content Item") { 0 } else { 1 } } }, Name
)

$serverContentItems = @{}
Get-DeployRContentItem -ErrorAction SilentlyContinue | ForEach-Object {
    $serverContentItems[[string]$_.id] = $_
}

foreach ($item in $orderedSelection) {
    try {
        Write-Host "Processing $($item.Type): $($item.Name)"

        if ($item.Type -eq "Content Item") {
            $existing = $serverContentItems[[string]$item.Id]

            if ($existing) {
                Write-Host "  Content item already exists; updating source files for $($item.Name)"

                $serverVersions = @{}
                foreach ($serverVersion in @($existing.versions)) {
                    $serverVersions[[string]$serverVersion.versionNo] = $true
                }

                foreach ($version in @($item.Definition.versions)) {
                    $versionNo = [string]$version.versionNo
                    if (-not $serverVersions.ContainsKey($versionNo)) {
                        Write-Warning "  Content item '$($item.Name)' exists on the server but version $versionNo does not; skipping content upload for that version."
                        continue
                    }

                    $sourceFolder = Join-Path -Path (Split-Path -Parent $item.SourceFile) -ChildPath (Join-Path -Path $item.Id -ChildPath $versionNo)
                    if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) {
                        throw "Content source folder not found: '$sourceFolder'."
                    }

                    Update-DeployRContentItemContent -ContentId $item.Id -ContentVersion $versionNo -SourceFolder $sourceFolder -ErrorAction Stop | Out-Null
                }
            }
            else {
                Write-Host "  Content item is new; importing metadata and source files for $($item.Name)"
                Import-DeployRContentItem -SourceFile $item.SourceFile -ErrorAction Stop | Out-Null
            }
        }
        else {
            Import-DeployRStepDefinition -SourceFile $item.SourceFile -Force -ErrorAction Stop | Out-Null
        }

        $results.Add([PSCustomObject]@{ Type = $item.Type; Name = $item.Name; Status = "Succeeded"; Error = "" })
        Write-Host "Succeeded: $($item.Name)" -ForegroundColor Green
    }
    catch {
        $results.Add([PSCustomObject]@{ Type = $item.Type; Name = $item.Name; Status = "Failed"; Error = $_.Exception.Message })
        Write-Error "Failed: $($item.Name): $($_.Exception.Message)" -ErrorAction Continue
    }
}

Write-Host ""
$results | Format-Table Type, Name, Status, Error -AutoSize

$failedCount = @($results | Where-Object Status -eq "Failed").Count
$succeededCount = $results.Count - $failedCount
Write-Host "Completed: $succeededCount succeeded, $failedCount failed."

if ($failedCount -gt 0) {
    exit 1
}
