@echo off
rem Thin wrapper around build_exe.ps1 so every Windows entrypoint uses yt-tool.spec.
rem Usage:
rem   scripts\build\windows\build_exe.bat [name] [clean] [with_ffmpeg]

setlocal
set "NAME=yt-tool"
set "CLEAN_ARG="
set "WITH_FFMPEG_ARG="

if not "%~1"=="" set "NAME=%~1"
if /I "%~2"=="clean" set "CLEAN_ARG=-Clean"
if /I "%~3"=="with_ffmpeg" set "WITH_FFMPEG_ARG=-WithFfmpeg"

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\..\..\.."
set "PROJECT_DIR=%CD%"
popd

set "POWERSHELL_CMD="
where pwsh >nul 2>&1 && set "POWERSHELL_CMD=pwsh"
if not defined POWERSHELL_CMD where powershell >nul 2>&1 && set "POWERSHELL_CMD=powershell"

if not defined POWERSHELL_CMD (
  echo PowerShell not found.
  exit /b 2
)

"%POWERSHELL_CMD%" -NoProfile -ExecutionPolicy Bypass -File "%PROJECT_DIR%\scripts\build\windows\build_exe.ps1" -Name "%NAME%" %CLEAN_ARG% %WITH_FFMPEG_ARG%
exit /b %ERRORLEVEL%
