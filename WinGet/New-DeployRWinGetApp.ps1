[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Display name of the application content item")]
    [string]$AppName,

    [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Winget application ID, e.g. Mozilla.Firefox")]
    [string]$AppID,

    [Parameter(Mandatory = $false)]
    [string]$Purpose = "Application",

    [Parameter(Mandatory = $false)]
    [string]$Type = "SingleFile",

    [Parameter(Mandatory = $false)]
    [string[]]$Tags = @("winget"),

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [ValidateSet("machine", "user")]
    [string]$Scope = "machine",

    [Parameter(Mandatory = $false)]
    [string]$Status = "Active",

    [Parameter(Mandatory = $false)]
    [string]$SuccessCodes = "0,3010",

    [Parameter(Mandatory = $false)]
    [string]$Source = "winget",

    [Parameter(Mandatory = $false)]
    [switch]$AcceptPackageAgreements,

    [Parameter(Mandatory = $false)]
    [switch]$AcceptSourceAgreements,

    [Parameter(Mandatory = $false)]
    [string]$WrapperScriptPath = ".\Install-WinGetApp.ps1",

    [Parameter(Mandatory = $false)]
    [switch]$Connect,

    [Parameter(Mandatory = $false)]
    [string]$Passcode
)

begin {
    function Write-Log {
        param (
            [string]$Message,
            [ValidateSet("Info", "Warning", "Error")]
            [string]$Level = "Info"
        )
        $colorMap = @{ "Info" = "White"; "Warning" = "Yellow"; "Error" = "Red" }
        Write-Host $Message -ForegroundColor $colorMap[$Level]
    }

    function Test-DeployRCommand {
        param (
            [string]$CommandName
        )
        $cmd = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "Required DeployR command '$CommandName' was not found. Ensure the DeployR.Utility module is imported and you are connected to the DeployR server."
        }
    }

    function Get-DeployRParameterName {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$CommandName,

            [Parameter(Mandatory = $true)]
            [string[]]$Candidates
        )

        $cmd = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "Command '$CommandName' was not found."
        }

        foreach ($candidate in $Candidates) {
            $matchingKey = $cmd.Parameters.Keys | Where-Object { $_ -eq $candidate } | Select-Object -First 1
            if ($matchingKey) {
                return $matchingKey
            }
        }

        throw "Could not find a matching parameter for '$CommandName'. Tried: $($Candidates -join ', ')"
    }

    if (-not (Test-Path -Path $WrapperScriptPath)) {
        throw "Wrapper script not found at '$WrapperScriptPath'. Update -WrapperScriptPath or run this script from the same folder as Install-WinGetApp.ps1."
    }

    try {
        Import-Module DeployR.Utility -ErrorAction Stop
        Write-Log -Message "DeployR.Utility module imported successfully."
    }
    catch {
        throw "Failed to import DeployR.Utility module. Make sure it is installed. Error: $_"
    }

    $requiredCommands = @("New-DeployRContentItem", "New-DeployRContentItemVersion", "Update-DeployRContentItemContent", "Set-DeployRMetadata")
    foreach ($command in $requiredCommands) {
        Test-DeployRCommand -CommandName $command
    }

    if ($Connect) {
        if ($Passcode) {
            Connect-DeployR -Passcode $Passcode | Out-Null
        }
        else {
            Connect-DeployR | Out-Null
        }
        Write-Log -Message "Connected to DeployR."
    }
}

process {
    $tagString = $Tags -join ","
    $installCommand = "pwsh.exe -file .\Install-WinGetApp.ps1 -AppID `"$AppID`" -Scope $Scope -Source $Source"

    if ($AcceptPackageAgreements) {
        $installCommand += " -AcceptPackageAgreements"
    }

    if ($AcceptSourceAgreements) {
        $installCommand += " -AcceptSourceAgreements"
    }

    Write-Log -Message "Preparing to create DeployR Application content item:"
    Write-Log -Message "  Name:        $AppName"
    Write-Log -Message "  AppID:       $AppID"
    Write-Log -Message "  Purpose:     $Purpose"
    Write-Log -Message "  Type:        $Type"
    Write-Log -Message "  Tags:        $tagString"

    $contentItemPurposeParam = Get-DeployRParameterName -CommandName "New-DeployRContentItem" -Candidates @("Purpose", "ContentPurpose")
    $contentItemTypeParam = Get-DeployRParameterName -CommandName "New-DeployRContentItem" -Candidates @("Type", "ContentType")
    $contentItemTagsParam = Get-DeployRParameterName -CommandName "New-DeployRContentItem" -Candidates @("Tags", "Tag") -ErrorAction SilentlyContinue

    $newItemParams = @{
        Name = $AppName
        $contentItemPurposeParam = $Purpose
        $contentItemTypeParam = $Type
    }

    if ($Description) {
        $newItemParams["Description"] = $Description
    }

    if ($contentItemTagsParam) {
        $newItemParams[$contentItemTagsParam] = $Tags
    }
    Write-Log -Message "  Install Cmd: $installCommand"

    if (-not $PSCmdlet.ShouldProcess("DeployR Content Item '$AppName'", "Create")) {
        return
    }

    try {
        $newItem = New-DeployRContentItem @newItemParams -ErrorAction Stop
        Write-Log -Message "Created content item '$AppName' with ID $($newItem.id)."
    }
    catch {
        throw "Failed to create DeployR content item. Verify the New-DeployRContentItem parameters match your DeployR module. Error: $_"
    }

    try {
        $versionContentItemIdParam = Get-DeployRParameterName -CommandName "New-DeployRContentItemVersion" -Candidates @("ContentItemId", "Id", "ContentItem")
        $versionCommandLineParam = Get-DeployRParameterName -CommandName "New-DeployRContentItemVersion" -Candidates @("InstallationCommandLine", "CommandLine")
        $versionSuccessCodeParam = Get-DeployRParameterName -CommandName "New-DeployRContentItemVersion" -Candidates @("InstallationSuccessCode", "SuccessCode")
        $versionDescriptionParam = Get-DeployRParameterName -CommandName "New-DeployRContentItemVersion" -Candidates @("Description") -ErrorAction SilentlyContinue
        $versionStatusParam = Get-DeployRParameterName -CommandName "New-DeployRContentItemVersion" -Candidates @("Status") -ErrorAction SilentlyContinue

        $newVersionParams = @{
            $versionContentItemIdParam = $newItem.id
            $versionCommandLineParam = $installCommand
            $versionSuccessCodeParam = $SuccessCodes
        }

        if ($versionDescriptionParam -and $Description) {
            $newVersionParams[$versionDescriptionParam] = $Description
        }

        if ($versionStatusParam) {
            $newVersionParams[$versionStatusParam] = $Status
        }

        $newVersion = New-DeployRContentItemVersion @newVersionParams -ErrorAction Stop

        Write-Log -Message "Created version $($newVersion.versionNo) for content item $($newItem.id)."

        if (-not $versionStatusParam -and $Status) {
            $versionTypeName = Get-DeployRParameterName -CommandName "Set-DeployRMetadata" -Candidates @("Type") -ErrorAction SilentlyContinue
            if ($versionTypeName) {
                $versionTypeValue = $null
                $versionTypeCandidates = @("ContentItemVersion", "ContentVersion", "Version")
                foreach ($candidate in $versionTypeCandidates) {
                    try {
                        $newVersion.status = $Status
                        Set-DeployRMetadata -Type $candidate -Object $newVersion -ErrorAction Stop | Out-Null
                        $versionTypeValue = $candidate
                        break
                    }
                    catch {
                        # Try next candidate
                    }
                }

                if ($versionTypeValue) {
                    Write-Log -Message "Set version $($newVersion.versionNo) status to '$Status' using Set-DeployRMetadata -Type $versionTypeValue."
                }
                else {
                    Write-Log -Message "WARNING: Could not set version status to '$Status' via Set-DeployRMetadata. You may need to activate the version manually in the DeployR dashboard." -Level "Warning"
                }
            }
            else {
                Write-Log -Message "WARNING: Could not determine how to set version status to '$Status'. You may need to activate the version manually in the DeployR dashboard." -Level "Warning"
            }
        }
    }
    catch {
        throw "Failed to create content item version. Verify the New-DeployRContentItemVersion parameters match your DeployR module. Error: $_"
    }

    try {
        $uploadIdParam = Get-DeployRParameterName -CommandName "Update-DeployRContentItemContent" -Candidates @("ContentId", "ContentItemId", "Id", "ContentItem", "ItemId")
        $uploadVersionParam = Get-DeployRParameterName -CommandName "Update-DeployRContentItemContent" -Candidates @("ContentVersion", "VersionNo", "Version")
        $uploadSourceParam = Get-DeployRParameterName -CommandName "Update-DeployRContentItemContent" -Candidates @("SourceFolder", "SourceFile", "Path")

        $wrapperFile = Resolve-Path -Path $WrapperScriptPath | Select-Object -ExpandProperty Path
        $sourceFolder = Join-Path -Path $env:TEMP -ChildPath "DeployRWinGet_$($newItem.id)"

        if (Test-Path -Path $sourceFolder) {
            Remove-Item -Path $sourceFolder -Recurse -Force
        }

        New-Item -ItemType Directory -Path $sourceFolder -Force | Out-Null
        Copy-Item -Path $wrapperFile -Destination $sourceFolder -Force

        $uploadParams = @{
            $uploadIdParam = $newItem.id
            $uploadVersionParam = $newVersion.versionNo
            $uploadSourceParam = $sourceFolder
        }

        Update-DeployRContentItemContent @uploadParams -ErrorAction Stop

        Write-Log -Message "Uploaded wrapper script to content item $($newItem.id), version $($newVersion.versionNo)."
    }
    catch {
        throw "Failed to upload wrapper script. Verify the Update-DeployRContentItemContent parameters match your DeployR module. Error: $_"
    }
    finally {
        if ($sourceFolder -and (Test-Path -Path $sourceFolder)) {
            Remove-Item -Path $sourceFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        $metadata = Get-DeployRContentItem -Id $newItem.id -ErrorAction Stop
        if (-not $metadata.tags) {
            $metadata | Add-Member -MemberType NoteProperty -Name "tags" -Value @() -Force
        }
        foreach ($tag in $Tags) {
            if ($metadata.tags -notcontains $tag) {
                $metadata.tags += $tag
            }
        }
        Set-DeployRMetadata -Type ContentItem -Object $metadata -ErrorAction Stop
        Write-Log -Message "Applied tags: $tagString"
    }
    catch {
        Write-Log -Message "WARNING: Content item was created but could not apply tags. You can add the '$tagString' tag manually in the DeployR dashboard. Error: $_" -Level "Warning"
    }

    [PSCustomObject]@{
        ContentItemId   = $newItem.id
        Name            = $AppName
        AppID           = $AppID
        VersionNo       = $newVersion.versionNo
        InstallCommand  = $installCommand
        Tags            = $tagString
        WrapperScript   = $WrapperScriptPath
    }
}
