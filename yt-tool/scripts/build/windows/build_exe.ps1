# Build Windows executable with PyInstaller using the project spec file.
# Usage:
#   .\scripts\build\windows\build_exe.ps1 [-Name yt-tool] [-Clean]

param(
    [string]$Name = "yt-tool",
    [switch]$Clean
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
    foreach ($cmd in @('py', 'python', 'python3')) {
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

# Download the yt-dlp standalone Windows binary so the .exe works without a system yt-dlp install.
$YtdlpDir = Join-Path $ProjectDir 'vendor\bin'
$YtdlpBin = Join-Path $YtdlpDir 'yt-dlp.exe'
if (-not (Test-Path $YtdlpDir)) {
    New-Item -ItemType Directory -Path $YtdlpDir | Out-Null
}
if ($Clean -or -not (Test-Path $YtdlpBin)) {
    Write-Host 'Downloading yt-dlp Windows binary...'
    $ProgressPreference = 'SilentlyContinue'  # speed up Invoke-WebRequest
    Invoke-WebRequest `
        -Uri 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' `
        -OutFile $YtdlpBin
    Write-Host "yt-dlp binary: $YtdlpBin"
} else {
    Write-Host "yt-dlp binary already present: $YtdlpBin"
}

# Use the project spec file — it handles collect_all(PySide6/shiboken6/yt_dlp)
# and bundles the yt-dlp standalone binary via _extra_binaries.
$pyArgs = @('-m', 'PyInstaller', '--noconfirm')
if ($Clean) {
    $pyArgs += '--clean'
}
$pyArgs += (Join-Path $ProjectDir 'yt-tool.spec')

if ($Python -eq 'py') {
    & $Python -3 @pyArgs
} else {
    & $Python @pyArgs
}

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Built: $ProjectDir\dist\$Name.exe (or dist\$Name\$Name.exe)"
