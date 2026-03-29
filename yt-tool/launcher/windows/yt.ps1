# ================================================================
# yt.ps1 — Windows 薄启动器 (PowerShell)
#
# 右键"使用 PowerShell 运行"或终端内执行。
# 职责：找到 Python → 启动 app 包 → 转发参数。
# 不做任何业务逻辑，所有核心逻辑在 Python 层。
# ================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 定位脚本自身所在目录，再向上两级到 yt-tool\
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectDir = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path

# 按优先级查找 Python 解释器
$Python = $null

foreach ($cmd in @('py', 'python', 'python3')) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        $Python = $cmd
        break
    }
}

if (-not $Python) {
    Write-Host '错误: 未找到 Python 解释器'
    Write-Host '请安装 Python 3: winget install Python.Python.3'
    Write-Host '或访问: https://www.python.org/downloads/'
    Write-Host ''
    Read-Host '按回车键退出'
    exit 1
}

Set-Location $ProjectDir

if ($Python -eq 'py') {
    & $Python -3 -m app @args
} else {
    & $Python -m app @args
}

$ExitCode = $LASTEXITCODE

Write-Host ''
Read-Host '按回车键退出'
exit $ExitCode
