# Build Windows executable with PyInstaller using the unified app entry.
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
$VenvPython = Join-Path $ProjectDir '.venv\\Scripts\\python.exe'
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

$args = @('-m', 'PyInstaller', '--noconfirm', '--windowed', '--name', $Name, '--paths', $ProjectDir, '--paths', (Join-Path $ProjectDir 'vendor'), 'app/__main__.py')
if ($Clean) {
    $args = @('-m', 'PyInstaller', '--noconfirm', '--clean', '--windowed', '--name', $Name, '--paths', $ProjectDir, '--paths', (Join-Path $ProjectDir 'vendor'), 'app/__main__.py')
}

if ($Python -eq 'py') {
    & $Python -3 @args
} else {
    & $Python @args
}

exit $LASTEXITCODE
