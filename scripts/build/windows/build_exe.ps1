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

if ($WithFfmpeg) {
    if ([string]::IsNullOrWhiteSpace($FfmpegUrl)) {
        throw 'Missing ffmpeg source URL. Set -FfmpegUrl or YT_TOOL_FFMPEG_WINDOWS_URL.'
    }
    if ([string]::IsNullOrWhiteSpace($FfmpegSha256)) {
        throw 'Missing ffmpeg SHA256. Set -FfmpegSha256 or YT_TOOL_FFMPEG_WINDOWS_SHA256.'
    }
    if ($FfmpegUrl -match '/latest/') {
        throw "Refuse mutable ffmpeg URL: $FfmpegUrl. Use a pinned, versioned archive URL."
    }

    $FfmpegBin = Join-Path $VendorBinDir 'ffmpeg.exe'
    $FfprobeBin = Join-Path $VendorBinDir 'ffprobe.exe'

    if ($Clean -or -not (Test-Path $FfmpegBin) -or -not (Test-Path $FfprobeBin)) {
        Write-Host 'Downloading ffmpeg archive...'
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("yt-tool-ffmpeg-" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        try {
            $archivePath = Join-Path $tempDir 'ffmpeg-win.zip'
            $oldProgressPreference = $ProgressPreference
            try {
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $FfmpegUrl -OutFile $archivePath
            } finally {
                $ProgressPreference = $oldProgressPreference
            }
            $actualSha = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $expectedSha = $FfmpegSha256.Trim().ToLowerInvariant()
            if ($actualSha -ne $expectedSha) {
                throw @(
                    'ffmpeg archive SHA256 mismatch.',
                    "  expected: $expectedSha",
                    "  actual  : $actualSha",
                    "  source  : $FfmpegUrl"
                ) -join [Environment]::NewLine
            }

            $extractDir = Join-Path $tempDir 'extract'
            Expand-Archive -Path $archivePath -DestinationPath $extractDir -Force

            $ffmpegSrc = Get-ChildItem -Path $extractDir -Recurse -File -Filter 'ffmpeg.exe' | Select-Object -First 1
            $ffprobeSrc = Get-ChildItem -Path $extractDir -Recurse -File -Filter 'ffprobe.exe' | Select-Object -First 1
            if ($null -eq $ffmpegSrc -or $null -eq $ffprobeSrc) {
                throw "ffmpeg archive does not contain ffmpeg.exe + ffprobe.exe: $FfmpegUrl"
            }

            Copy-Item -Path $ffmpegSrc.FullName -Destination $FfmpegBin -Force
            Copy-Item -Path $ffprobeSrc.FullName -Destination $FfprobeBin -Force
        } finally {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "ffmpeg binary: $FfmpegBin"
        Write-Host "ffprobe binary: $FfprobeBin"
    } else {
        Write-Host "ffmpeg binaries already present: $FfmpegBin / $FfprobeBin"
    }
}

# Use the project spec file — it handles collect_all(PySide6/shiboken6/yt_dlp)
# and bundles optional helper binaries (ffmpeg / ffprobe) via _extra_binaries.
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
