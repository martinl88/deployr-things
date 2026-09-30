#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ImagePath = (Join-Path -Path $PSScriptRoot -ChildPath "install.wim"),

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$ImportToDeployR
)

$ErrorActionPreference = "Stop"

function Get-WindowsRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Build
    )

    $releases = @{
        10240 = "1507"
        10586 = "1511"
        14393 = "1607"
        15063 = "1703"
        16299 = "1709"
        17134 = "1803"
        17763 = "1809"
        18362 = "1903"
        18363 = "1909"
        19041 = "2004"
        19042 = "20H2"
        19043 = "21H1"
        19044 = "21H2"
        19045 = "22H2"
        22000 = "21H2"
        22621 = "22H2"
        22631 = "23H2"
        26100 = "24H2"
        26200 = "25H2"
        26300 = "26H2"
    }

    if ($releases.ContainsKey($Build)) {
        return $releases[$Build]
    }

    return ""
}

function Get-ArchitectureName {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Architecture
    )

    $architectureValue = [string]$Architecture
    $architectures = @{
        "0" = "x86"
        "5" = "ARM"
        "6" = "IA64"
        "9" = "x64"
        "12" = "ARM64"
        "Intel" = "x86"
        "Amd64" = "x64"
    }

    if ($architectures.ContainsKey($architectureValue)) {
        return $architectures[$architectureValue]
    }

    return $architectureValue
}

function ConvertTo-SafeFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()
    $escapedCharacters = [Regex]::Escape((-join $invalidCharacters))
    $safeName = [Regex]::Replace($Name, "[$escapedCharacters]", "-")
    $safeName = [Regex]::Replace($safeName, "\s+", " ").Trim().TrimEnd(".")

    if ([string]::IsNullOrWhiteSpace($safeName)) {
        return "Windows Edition"
    }

    return $safeName
}

function Get-EditionFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Edition
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($Edition.Name)

    if ($Edition.Release) {
        $parts.Add($Edition.Release)
    }

    if ($Edition.Version) {
        $parts.Add("($($Edition.Version))")
    }

    if ($Edition.Architecture) {
        $parts.Add($Edition.Architecture)
    }

    if ($Edition.Language) {
        $parts.Add($Edition.Language)
    }

    return "$(ConvertTo-SafeFileName -Name ($parts -join " ")).wim"
}

function Get-DeployRParameterName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [string[]]$Candidates,

        [Parameter()]
        [switch]$AllowMissing
    )

    $command = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Required DeployR command '$CommandName' was not found."
    }

    foreach ($candidate in $Candidates) {
        $matchingName = $command.Parameters.Keys | Where-Object { $_ -eq $candidate } | Select-Object -First 1
        if ($matchingName) {
            return $matchingName
        }
    }

    if ($AllowMissing) {
        return $null
    }

    throw "Could not find a supported parameter on '$CommandName'. Tried: $($Candidates -join ', ')."
}

function Get-DeployRValidatedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName,

        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    $parameter = (Get-Command -Name $CommandName -ErrorAction Stop).Parameters[$ParameterName]
    $validateSet = $parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1
    if ($validateSet) {
        foreach ($candidate in $Candidates) {
            $match = $validateSet.ValidValues | Where-Object { $_ -eq $candidate } | Select-Object -First 1
            if ($match) {
                return $match
            }
        }
    }

    return $Candidates[0]
}

function Import-DeployRPrerequisites {
    $modulePath = "C:\Program Files\2Pint Software\DeployR\Client\PSModules\DeployR.Utility"
    try {
        Import-Module "DeployR.Utility" -ErrorAction Stop
    }
    catch {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            throw "DeployR.Utility could not be imported and was not found at '$modulePath'. Connect to DeployR before running this script."
        }
        Import-Module $modulePath -ErrorAction Stop
    }

    foreach ($command in @("New-DeployRContentItem", "New-DeployRContentItemVersion", "Update-DeployRContentItemContent", "Get-DeployRContentItem", "Set-DeployRMetadata")) {
        if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
            throw "Required DeployR command '$command' was not found after importing DeployR.Utility."
        }
    }
}

function Get-DeployRDescription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Edition
    )

    $details = @(
        $Edition.Description
        if ($Edition.Version) { "Version $($Edition.Version)" }
        if ($Edition.Architecture) { $Edition.Architecture }
        if ($Edition.Language) { $Edition.Language }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    return $details -join " | "
}

function Get-DeployRTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Edition
    )

    return @("Windows", $Edition.Release, $Edition.Architecture, $Edition.Language) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        Select-Object -Unique
}

function New-DeployROperatingSystemVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ContentItem,

        [Parameter(Mandatory = $true)]
        $Edition
    )

    $idParameter = Get-DeployRParameterName -CommandName "New-DeployRContentItemVersion" -Candidates @("ContentItemId", "Id", "ContentItem")
    $descriptionParameter = Get-DeployRParameterName -CommandName "New-DeployRContentItemVersion" -Candidates @("Description") -AllowMissing
    $statusParameter = Get-DeployRParameterName -CommandName "New-DeployRContentItemVersion" -Candidates @("Status") -AllowMissing
    $parameters = @{ $idParameter = $ContentItem.id }

    if ($descriptionParameter) {
        $parameters[$descriptionParameter] = Get-DeployRDescription -Edition $Edition
    }
    if ($statusParameter) {
        $parameters[$statusParameter] = "Active"
    }

    return New-DeployRContentItemVersion @parameters -ErrorAction Stop
}

function New-DeployROperatingSystemItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        $Edition,

        [Parameter(Mandatory = $true)]
        [string[]]$Tags
    )

    $purposeParameter = Get-DeployRParameterName -CommandName "New-DeployRContentItem" -Candidates @("Purpose", "ContentPurpose")
    $typeParameter = Get-DeployRParameterName -CommandName "New-DeployRContentItem" -Candidates @("Type", "ContentType")
    $tagsParameter = Get-DeployRParameterName -CommandName "New-DeployRContentItem" -Candidates @("Tags", "Tag") -AllowMissing
    $descriptionParameter = Get-DeployRParameterName -CommandName "New-DeployRContentItem" -Candidates @("Description") -AllowMissing
    $parameters = @{
        Name = $Name
        $purposeParameter = Get-DeployRValidatedValue -CommandName "New-DeployRContentItem" -ParameterName $purposeParameter -Candidates @("OperatingSystem", "Operating System")
        $typeParameter = Get-DeployRValidatedValue -CommandName "New-DeployRContentItem" -ParameterName $typeParameter -Candidates @("SingleFile", "Single File")
    }

    if ($descriptionParameter) {
        $parameters[$descriptionParameter] = Get-DeployRDescription -Edition $Edition
    }
    if ($tagsParameter) {
        $parameters[$tagsParameter] = $Tags
    }

    $contentItem = New-DeployRContentItem @parameters -ErrorAction Stop
    if (-not $tagsParameter -and $Tags.Count -gt 0) {
        $metadata = Get-DeployRContentItem -Id $contentItem.id -ErrorAction Stop
        if (-not $metadata.tags) {
            $metadata | Add-Member -MemberType NoteProperty -Name "tags" -Value @() -Force
        }
        foreach ($tag in $Tags) {
            if ($metadata.tags -notcontains $tag) {
                $metadata.tags += $tag
            }
        }
        Set-DeployRMetadata -Type ContentItem -Object $metadata -ErrorAction Stop | Out-Null
    }

    return $contentItem
}

function Send-WimToDeployR {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WimPath,

        [Parameter(Mandatory = $true)]
        $ContentItem,

        [Parameter(Mandatory = $true)]
        $Version
    )

    $idParameter = Get-DeployRParameterName -CommandName "Update-DeployRContentItemContent" -Candidates @("ContentId", "ContentItemId", "Id", "ContentItem", "ItemId")
    $versionParameter = Get-DeployRParameterName -CommandName "Update-DeployRContentItemContent" -Candidates @("ContentVersion", "VersionNo", "Version")
    $sourceParameter = Get-DeployRParameterName -CommandName "Update-DeployRContentItemContent" -Candidates @("SourceFolder", "SourceFile", "Path")
    $stagingPath = Join-Path -Path (Split-Path -Parent $WimPath) -ChildPath ".deployr-staging-$([System.Guid]::NewGuid().ToString())"

    try {
        New-Item -Path $stagingPath -ItemType Directory -ErrorAction Stop | Out-Null
        $stagedWim = Join-Path -Path $stagingPath -ChildPath (Split-Path -Leaf $WimPath)
        try {
            New-Item -Path $stagedWim -ItemType HardLink -Value $WimPath -ErrorAction Stop | Out-Null
        }
        catch {
            Copy-Item -LiteralPath $WimPath -Destination $stagedWim -Force -ErrorAction Stop
        }

        $parameters = @{
            $idParameter = $ContentItem.id
            $versionParameter = $Version.versionNo
            $sourceParameter = $stagingPath
        }
        Update-DeployRContentItemContent @parameters -ErrorAction Stop | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

foreach ($command in @("Get-WindowsImage", "Export-WindowsImage", "Out-GridView")) {
    if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' is not available. Run this script in Windows PowerShell with the DISM module and Out-GridView installed."
    }
}

if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
    throw "WIM file not found: '$ImagePath'."
}

$sourceImage = Get-Item -LiteralPath $ImagePath
if ($sourceImage.Extension -ne ".wim") {
    throw "ImagePath must reference a .wim file: '$($sourceImage.FullName)'."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path -Path $sourceImage.DirectoryName -ChildPath "Editions"
}
$outputDirectory = [System.IO.Path]::GetFullPath($OutputPath)

$imageSummaries = @(Get-WindowsImage -ImagePath $sourceImage.FullName)
if ($imageSummaries.Count -eq 0) {
    Write-Warning "No editions were found in '$($sourceImage.FullName)'."
    return
}

$editions = @(
    foreach ($summary in $imageSummaries) {
        $image = Get-WindowsImage -ImagePath $sourceImage.FullName -Index $summary.ImageIndex
        $version = [string]$image.Version
        $build = 0
        if ($image.Version -and $image.Version.Build -ge 0) {
            $build = $image.Version.Build
        }
        elseif ($version -match "^(?:\d+\.){2}(\d+)") {
            $build = [int]$Matches[1]
        }

        $languages = @($image.Languages | ForEach-Object { [string]$_ } | Where-Object { $_ })
        $language = $languages -join ","
        $name = [string]$image.ImageName
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = [string]$summary.ImageName
        }
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = "Windows Edition $($summary.ImageIndex)"
        }

        [PSCustomObject]@{
            Index            = [int]$summary.ImageIndex
            Name             = $name
            Release          = if ($build -gt 0) { Get-WindowsRelease -Build $build } else { "" }
            Version          = $version
            Architecture     = Get-ArchitectureName -Architecture $image.Architecture
            Language         = $language
            EditionId        = [string]$image.EditionId
            InstallationType = [string]$image.InstallationType
            Description      = [string]$image.ImageDescription
        }
    }
)

$selection = @(
    $editions |
        Select-Object Index, Name, Release, Version, Architecture, Language, EditionId, InstallationType, Description |
        Out-GridView -Title "Select Windows editions to export (Ctrl/Shift for multiple)" -PassThru
)

if ($selection.Count -eq 0) {
    Write-Host "No editions selected. No files were exported."
    return
}

$exportJobs = [System.Collections.Generic.List[object]]::new()
$usedNames = @{}
foreach ($edition in $selection) {
    $fileName = Get-EditionFileName -Edition $edition
    $nameKey = $fileName.ToLowerInvariant()
    if ($usedNames.ContainsKey($nameKey)) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $fileName = "$baseName - Index $($edition.Index).wim"
    }
    $usedNames[$fileName.ToLowerInvariant()] = $true

    $destinationPath = Join-Path -Path $outputDirectory -ChildPath $fileName
    if ([System.StringComparer]::OrdinalIgnoreCase.Equals($sourceImage.FullName, [System.IO.Path]::GetFullPath($destinationPath))) {
        throw "The generated destination path matches the source WIM: '$destinationPath'. Choose a different OutputPath."
    }

    $exportJobs.Add([PSCustomObject]@{
        Edition         = $edition
        DestinationPath = $destinationPath
    })
}

if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($job in $exportJobs) {
    try {
        if (Test-Path -LiteralPath $job.DestinationPath) {
            Remove-Item -LiteralPath $job.DestinationPath -Force
        }

        Write-Host "Exporting index $($job.Edition.Index) ($($job.Edition.Name)) to '$($job.DestinationPath)'..."
        Export-WindowsImage -SourceImagePath $sourceImage.FullName -SourceIndex $job.Edition.Index -DestinationImagePath $job.DestinationPath -CompressionType Max -CheckIntegrity | Out-Null
        $results.Add([PSCustomObject]@{ Index = $job.Edition.Index; Edition = $job.Edition.Name; Status = "Succeeded"; Path = $job.DestinationPath; Error = ""; Job = $job })
        Write-Host "Succeeded: $($job.Edition.Name)" -ForegroundColor Green
    }
    catch {
        $results.Add([PSCustomObject]@{ Index = $job.Edition.Index; Edition = $job.Edition.Name; Status = "Failed"; Path = $job.DestinationPath; Error = $_.Exception.Message; Job = $job })
        Write-Error "Failed to export $($job.Edition.Name): $($_.Exception.Message)" -ErrorAction Continue
    }
}

Write-Host ""
$results | Format-Table Index, Edition, Status, Path, Error -AutoSize

$failedCount = @($results | Where-Object Status -eq "Failed").Count
$succeededResults = @($results | Where-Object Status -eq "Succeeded")
Write-Host "Export completed: $($succeededResults.Count) succeeded, $failedCount failed."

$shouldImport = $ImportToDeployR.IsPresent
if (-not $shouldImport -and $succeededResults.Count -gt 0) {
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Import the exported WIMs into DeployR."),
        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Leave DeployR unchanged.")
    )
    $shouldImport = $Host.UI.PromptForChoice("DeployR import", "Import $($succeededResults.Count) successfully exported WIM(s) into DeployR?", $choices, 1) -eq 0
}

$importResults = [System.Collections.Generic.List[object]]::new()
if ($shouldImport -and $succeededResults.Count -gt 0) {
    Import-DeployRPrerequisites
    $existingItems = @(Get-DeployRContentItem -ErrorAction Stop)

    foreach ($result in $succeededResults) {
        $job = $result.Job
        $contentName = "OS - $([System.IO.Path]::GetFileNameWithoutExtension($job.DestinationPath))"
        $tags = @(Get-DeployRTags -Edition $job.Edition)
        $contentItem = $existingItems | Where-Object { [string]$_.name -eq $contentName } | Select-Object -First 1
        $createdItem = $false

        try {
            if (-not $contentItem) {
                Write-Host "Creating DeployR Operating System content item '$contentName'..."
                $contentItem = New-DeployROperatingSystemItem -Name $contentName -Edition $job.Edition -Tags $tags
                $existingItems += $contentItem
                $createdItem = $true
            }
            else {
                Write-Host "Adding a new version to existing DeployR content item '$contentName'..."
            }

            $version = New-DeployROperatingSystemVersion -ContentItem $contentItem -Edition $job.Edition
            Send-WimToDeployR -WimPath $job.DestinationPath -ContentItem $contentItem -Version $version
            $importResults.Add([PSCustomObject]@{ Edition = $job.Edition.Name; Status = "Succeeded"; ContentItemId = $contentItem.id; Version = $version.versionNo; CreatedItem = $createdItem; Error = "" })
            Write-Host "Imported: $contentName (content item $($contentItem.id), version $($version.versionNo))" -ForegroundColor Green
        }
        catch {
            $contentItemId = if ($contentItem) { [string]$contentItem.id } else { "" }
            $importResults.Add([PSCustomObject]@{ Edition = $job.Edition.Name; Status = "Failed"; ContentItemId = $contentItemId; Version = ""; CreatedItem = $createdItem; Error = $_.Exception.Message })
            Write-Error "Failed to import '$contentName' into DeployR: $($_.Exception.Message)" -ErrorAction Continue
        }
    }

    Write-Host ""
    $importResults | Format-Table Edition, Status, ContentItemId, Version, CreatedItem, Error -AutoSize
}

$importFailedCount = @($importResults | Where-Object Status -eq "Failed").Count
$importSucceededCount = @($importResults | Where-Object Status -eq "Succeeded").Count
if ($shouldImport) {
    Write-Host "DeployR import completed: $importSucceededCount succeeded, $importFailedCount failed."
}
else {
    Write-Host "DeployR import skipped."
}

if ($failedCount -gt 0 -or $importFailedCount -gt 0) {
    exit 1
}
