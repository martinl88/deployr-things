#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$FontPath = '',

    [Parameter(Mandatory = $false)]
    [bool]$Recurse = $true,

    [Parameter(Mandatory = $false)]
    [string]$LogFile = 'C:\_2P\Logs\FontInstall.log'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet(1, 2, 3)]
        [int]$Type = 1
    )

    $folder = Split-Path -Path $LogFile -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    $time = Get-Date -Format 'HH:mm:ss.ffffff'
    $date = Get-Date -Format 'MM-dd-yyyy'
    "<![LOG[$Message]LOG]!><time=`"$time`" date=`"$date`" component=`"FontInstall`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">" | Out-File -Append -Encoding UTF8 -FilePath $LogFile
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

try {
    Import-Module DeployR.Utility -ErrorAction SilentlyContinue
}
catch {
    # Module is not available outside of the task sequence environment
}

if (-not $FontPath) {
    # DeployR stores the downloaded folder for a Content option in _CONTENT-<optionName>
    $FontPath = Get-TaskSequenceValue -Name '_CONTENT-FontContent'
}
$tsRecurse = Get-TaskSequenceValue -Name 'Recurse'
if ($null -ne $tsRecurse -and $tsRecurse -ne '') {
    $Recurse = [bool]::Parse($tsRecurse)
}

if (-not $FontPath -or -not (Test-Path -LiteralPath $FontPath -PathType Container)) {
    Write-Log -Message "Font source folder not found: '$FontPath'" -Type 3
    Exit-WithCode -ExitCode 1
}

# Font resource P/Invoke helpers (adapted from Add-Font.ps1)
$fontCSharpCode = @'
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace FontResource
{
    public class AddRemoveFonts
    {
        private const uint WM_FONTCHANGE = 0x001D;
        private static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);

        [DllImport("gdi32.dll")]
        private static extern int AddFontResource(string lpFilename);

        [return: MarshalAs(UnmanagedType.Bool)]
        [DllImport("user32.dll")]
        private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        public static int AddFont(string fontFilePath) {
            if (!File.Exists(fontFilePath))
            {
                return 0;
            }
            try
            {
                int retVal = AddFontResource(fontFilePath);
                PostMessage(HWND_BROADCAST, WM_FONTCHANGE, IntPtr.Zero, IntPtr.Zero);
                return retVal;
            }
            catch
            {
                return 0;
            }
        }
    }
}
'@
Add-Type -TypeDefinition $fontCSharpCode

# Valid font extensions and registry display-name suffixes
$hashFontFileTypes = @{
    '.fon' = ''
    '.fnt' = ''
    '.ttf' = ' (TrueType)'
    '.ttc' = ' (TrueType)'
    '.otf' = ' (OpenType)'
}

$fontRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$fontsFolderPath = (New-Object -ComObject 'Shell.Application').Namespace(0x14).Self.Path
Write-Log -Message "Installing fonts from '$FontPath' to '$fontsFolderPath' (Recurse=$Recurse)"

function Add-SingleFont {
    param([string]$FilePath)

    $resolvedPath = (Resolve-Path -LiteralPath $FilePath).Path
    $fileDir = Split-Path -Path $resolvedPath -Parent
    $fileName = Split-Path -Path $resolvedPath -Leaf
    $fileExt = (Get-Item -LiteralPath $resolvedPath).Extension.ToLowerInvariant()
    $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

    $shell = New-Object -ComObject 'Shell.Application'
    $folder = $shell.Namespace($fileDir)
    $fontName = $folder.GetDetailsOf($folder.Items().Item($fileName), 21)
    if (-not $fontName) { $fontName = $fileBaseName }

    Copy-Item -LiteralPath $resolvedPath -Destination $fontsFolderPath -Force
    $fontFinalPath = Join-Path -Path $fontsFolderPath -ChildPath $fileName
    $retVal = [FontResource.AddRemoveFonts]::AddFont($fontFinalPath)

    if ($retVal -eq 0) {
        Write-Log -Message "Font '$resolvedPath' installation failed" -Type 3
        return $false
    }

    Write-Log -Message "Font '$resolvedPath' installed successfully"
    Set-ItemProperty -Path $fontRegistryPath -Name "$fontName$($hashFontFileTypes[$fileExt])" -Value $fileName -Type String
    return $true
}

$getChildItemArgs = @{
    LiteralPath = $FontPath
    File        = $true
    Recurse     = $Recurse
}
$fontFiles = @(Get-ChildItem @getChildItemArgs | Where-Object { $hashFontFileTypes.ContainsKey($_.Extension.ToLowerInvariant()) })

if ($fontFiles.Count -eq 0) {
    Write-Log -Message "No font files found in '$FontPath'" -Type 3
    Exit-WithCode -ExitCode 1
}

$failedCount = 0
foreach ($file in $fontFiles) {
    try {
        if (-not (Add-SingleFont -FilePath $file.FullName)) {
            $failedCount++
        }
    }
    catch {
        Write-Log -Message "An error occurred installing '$($file.FullName)': $($_.Exception.Message)" -Type 3
        $failedCount++
    }
}

$installedCount = $fontFiles.Count - $failedCount
if ($failedCount -gt 0) {
    Write-Log -Message "Completed with errors: $installedCount installed, $failedCount failed" -Type 3
    Exit-WithCode -ExitCode 1
}

Write-Log -Message "Completed: $installedCount font(s) installed"
Exit-WithCode -ExitCode 0
