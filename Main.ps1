<#
.SYNOPSIS
IPAP Workflow - 漫画翻译准备自动化工具启动脚本

.DESCRIPTION
启动 IPAP 工作流，导入必要的模块并执行主工作流。

.NOTES
Author: IPAP Team
Version: 1.0.0
Date: 2026-04-14
#>

# $Global:Logger 是 PoShLog 的设计约定，Write-InfoLog 跨模块访问需要全局作用域
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
param()

# Ensure PowerShell 7 or above
if ($PSVersionTable.PSVersion.Major -lt 7)
{
    Write-ErrorLog '错误: 需要 PowerShell 7 或更高版本'
    exit 1
}
# 设置控制台输出编码为 UTF-8，以支持特殊字符（如 ✓）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 导入 PoShLog 模块
$PoShLogPath = Join-Path $PSScriptRoot 'Modules\PoShLog'
Import-Module -Name $PoShLogPath -Force -Scope Global

# Initialize Logger in the Global scope so all modules can see it
$Global:Logger = New-Logger |
    Set-MinimumLevel -Value Verbose |
    Add-SinkConsole |
    Start-Logger

Write-InfoLog '✓ PoShLog 模块已导入'


# 导入 IPAP.Configuration 模块
$configModulePath = Join-Path $PSScriptRoot 'Modules\IPAP.Configuration\IPAP.Configuration.psd1'
Import-Module $configModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.Configuration 模块已导入'

# 初始化配置
Get-Configuration -ProjectRoot $PSScriptRoot | Out-Null
Write-InfoLog '✓ IPAP 配置已初始化'

# 获取项目根目录（后续模块路径使用）
$ProjectRoot = (Get-Configuration).Paths.ProjectRoot


# Import modules
Write-InfoLog '正在导入 IPAP 模块...'

# Import IPAP.Core module
$coreModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psd1'
Import-Module $coreModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.Core 模块已导入'

# Import IPAP.ImageProcessor module
$imageProcessorModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1'
Import-Module $imageProcessorModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.ImageProcessor 模块已导入'

# Import IPAP.ProjectManager module
$projectManagerModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1'
Import-Module $projectManagerModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.ProjectManager 模块已导入'

# Import IPAP.Workflow module
$workflowModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psd1'

Import-Module $workflowModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.Workflow 模块已导入'

# Execute main workflow
# 确认项目配置，获取用户确认后的配置实例
$Config = Confirm-ProjectConfiguration
Start-IPAPWorkflow -Config $Config
