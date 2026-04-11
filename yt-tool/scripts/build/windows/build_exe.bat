@echo off
rem Build Windows executable with PyInstaller using unified app entry.
rem Usage:
rem   scripts\build\windows\build_exe.bat [name] [clean]

setlocal
set "NAME=yt-tool"
set "CLEAN="

if not "%~1"=="" set "NAME=%~1"
if /I "%~2"=="clean" set "CLEAN=--clean"

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\..\..\.."
set "PROJECT_DIR=%CD%"
popd

if exist "%PROJECT_DIR%\.venv\Scripts\python.exe" goto :use_venv_python
where py >nul 2>&1 && goto :use_py
where python >nul 2>&1 && goto :use_python
where python3 >nul 2>&1 && goto :use_python3

echo Python not found.
exit /b 2

:use_venv_python
"%PROJECT_DIR%\.venv\Scripts\python.exe" -c "import PyInstaller" >nul 2>&1
if errorlevel 1 goto :no_pyinstaller_venv
cd /d "%PROJECT_DIR%"
"%PROJECT_DIR%\.venv\Scripts\python.exe" -m PyInstaller --noconfirm %CLEAN% --windowed --name "%NAME%" --paths "%PROJECT_DIR%" --paths "%PROJECT_DIR%\vendor" app\__main__.py
exit /b %ERRORLEVEL%

:no_pyinstaller_venv
echo PyInstaller not installed. Install with: .venv\Scripts\python.exe -m pip install pyinstaller
exit /b 2

:use_py
py -3 -c "import PyInstaller" >nul 2>&1
if errorlevel 1 goto :no_pyinstaller_py
cd /d "%PROJECT_DIR%"
py -3 -m PyInstaller --noconfirm %CLEAN% --windowed --name "%NAME%" --paths "%PROJECT_DIR%" --paths "%PROJECT_DIR%\vendor" app\__main__.py
exit /b %ERRORLEVEL%

:no_pyinstaller_py
echo PyInstaller not installed. Install with: py -3 -m pip install pyinstaller
exit /b 2

:use_python
python -c "import PyInstaller" >nul 2>&1
if errorlevel 1 goto :no_pyinstaller_python
cd /d "%PROJECT_DIR%"
python -m PyInstaller --noconfirm %CLEAN% --windowed --name "%NAME%" --paths "%PROJECT_DIR%" --paths "%PROJECT_DIR%\vendor" app\__main__.py
exit /b %ERRORLEVEL%

:no_pyinstaller_python
echo PyInstaller not installed. Install with: python -m pip install pyinstaller
exit /b 2

:use_python3
python3 -c "import PyInstaller" >nul 2>&1
if errorlevel 1 goto :no_pyinstaller_python3
cd /d "%PROJECT_DIR%"
python3 -m PyInstaller --noconfirm %CLEAN% --windowed --name "%NAME%" --paths "%PROJECT_DIR%" --paths "%PROJECT_DIR%\vendor" app\__main__.py
exit /b %ERRORLEVEL%

:no_pyinstaller_python3
echo PyInstaller not installed. Install with: python3 -m pip install pyinstaller
exit /b 2
