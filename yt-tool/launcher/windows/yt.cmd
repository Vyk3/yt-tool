@echo off
rem ================================================================
rem yt.cmd — Windows 薄启动器 (CMD)
rem
rem 双击即可运行。职责：找到 Python → 启动 app 包 → 转发参数。
rem 不做任何业务逻辑，所有核心逻辑在 Python 层。
rem ================================================================

setlocal

rem 定位脚本自身所在目录，再向上两级到 yt-tool\
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%\..\.."
set "PROJECT_DIR=%CD%"
popd

where py >nul 2>&1 && goto :use_py
where python >nul 2>&1 && goto :use_python
where python3 >nul 2>&1 && goto :use_python3

echo 错误: 未找到 Python 解释器
echo 请安装 Python 3: winget install Python.Python.3
echo 或访问: https://www.python.org/downloads/
echo.
pause
exit /b 1

:use_py
cd /d "%PROJECT_DIR%"
py -3 -m app %*
set "EXITCODE=%ERRORLEVEL%"
goto :end

:use_python
cd /d "%PROJECT_DIR%"
python -m app %*
set "EXITCODE=%ERRORLEVEL%"
goto :end

:use_python3
cd /d "%PROJECT_DIR%"
python3 -m app %*
set "EXITCODE=%ERRORLEVEL%"
goto :end

:end
echo.
pause
exit /b %EXITCODE%
