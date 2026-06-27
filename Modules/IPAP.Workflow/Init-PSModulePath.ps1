# 将项目 Modules 目录添加到 PSModulePath，确保 using module 指令能发现同项目的其他模块
# 此脚本由 IPAP.Workflow.psd1 的 ScriptsToProcess 在模块加载前执行
$modulesPath = Join-Path $PSScriptRoot '..'
if ($env:PSModulePath -notmatch [regex]::Escape($modulesPath))
{
    $env:PSModulePath = "$modulesPath;$env:PSModulePath"
}
