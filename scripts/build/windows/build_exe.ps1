# Build Windows executable with PyInstaller using the project spec file.
# Usage:
#   .\scripts\build\windows\build_exe.ps1 [-Name yt-tool] [-Clean]
#                                          [-WithFfmpeg] [-FfmpegUrl <url>]
#                                          [-FfmpegSha256 <hex>]

param(
    [string]$Name = "yt-tool",
    [switch]$Clean,
    [switch]$WithFfmpeg,
    [string]$FfmpegUrl = $env:YT_TOOL_FFMPEG_WINDOWS_URL,
    [string]$FfmpegSha256 = $env:YT_TOOL_FFMPEG_WINDOWS_SHA256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = (Resolve-Path (Join-Path $ScriptDir '..\..\..')).Path

$Python = $null
$VenvPython = Join-Path $ProjectDir '.venv\Scripts\python.exe'
if (Test-Path $VenvPython) {
    $Python = $VenvPython
} else {
    # Prefer setup-python managed interpreter on CI runners.
    foreach ($cmd in @('python', 'python3', 'py')) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            $Python = $cmd
            break
        }
    }
}
if (-not $Python) {
    Write-Error 'Python not found.'
}

$checkCmd = if ($Python -eq 'py') { @('-3', '-c', 'import PyInstaller') } else { @('-c', 'import PyInstaller') }
& $Python @checkCmd *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'PyInstaller is not installed in current environment.'
    if ($Python -eq 'py') {
        Write-Host 'Install it with: py -3 -m pip install pyinstaller'
    } else {
        Write-Host "Install it with: $Python -m pip install pyinstaller"
    }
    exit 2
}

Set-Location $ProjectDir

$VendorBinDir = Join-Path $ProjectDir 'vendor\bin'
if (-not (Test-Path $VendorBinDir)) {
    New-Item -ItemType Directory -Path $VendorBinDir | Out-Null
}

if ($Clean -and -not $WithFfmpeg) {
    # Prevent a prior -WithFfmpeg build from polluting the clean baseline build.
    foreach ($staleBinary in @('ffmpeg.exe', 'ffprobe.exe')) {
        $stalePath = Join-Path $VendorBinDir $staleBinary
        if (Test-Path $stalePath) {
            Remove-Item -Force $stalePath
        }
    }
}

if ($WithFfmpeg) {
    $prepareScript = Join-Path $ProjectDir 'scripts\build\common\prepare_ffmpeg.py'
    $prepareArgs = @(
        $prepareScript,
        '--platform', 'windows',
        '--vendor-bin-dir', $VendorBinDir,
        '--ffmpeg-url', $FfmpegUrl,
        '--ffmpeg-sha256', $FfmpegSha256
    )
    if ($Clean) {
        $prepareArgs += '--clean'
    }
    if ($Python -eq 'py') {
        & $Python -3 @prepareArgs
    } else {
        & $Python @prepareArgs
    }
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

# Use the project spec file — it handles collect_all(PySide6/shiboken6/yt_dlp)
# and bundles optional helper binaries (ffmpeg / ffprobe) via _extra_binaries.
$pyArgs = @('-m', 'PyInstaller', '--noconfirm')
if ($Clean) {
    $pyArgs += '--clean'
}
$pyArgs += (Join-Path $ProjectDir 'yt-tool.spec')
$env:YT_TOOL_BUILD_NAME = $Name

try {
    if ($Python -eq 'py') {
        & $Python -3 @pyArgs
    } else {
        & $Python @pyArgs
    }
}
finally {
    Remove-Item Env:\YT_TOOL_BUILD_NAME -ErrorAction SilentlyContinue
}

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Built: $ProjectDir\dist\$Name.exe (or dist\$Name\$Name.exe)"
