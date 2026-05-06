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

# Ensure PowerShell 7 or above
if ($PSVersionTable.PSVersion.Major -lt 7)
{
    Write-ErrorLog 'Error: PowerShell 7 or above is required'
    exit 1
}
# 设置控制台输出编码为 UTF-8，以支持特殊字符（如 ✓）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Global:ProjectRoot = $PSScriptRoot

# Import PoShLog module
$PoShLogPath = Join-Path $Global:ProjectRoot 'Modules\PoShLog'
Import-Module -Name $PoShLogPath -Force -Scope Global

# Initialize Logger in the Global scope so all modules can see it
& {
    $Global:Logger = New-Logger |
        Set-MinimumLevel -Value Verbose |
        Add-SinkConsole |
        Start-Logger
}

Write-InfoLog '✓ PoShLog module imported'


# Import modules
Write-InfoLog 'Importing IPAP modules...'

# Import IPAP.Core module
$coreModulePath = Join-Path $Global:ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psd1'
Import-Module $coreModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.Core module imported'

# Import IPAP.ImageProcessor module
$imageProcessorModulePath = Join-Path $Global:ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1'
Import-Module $imageProcessorModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.ImageProcessor module imported'

# Import IPAP.ProjectManager module
$projectManagerModulePath = Join-Path $Global:ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1'
Import-Module $projectManagerModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.ProjectManager module imported'

# Import IPAP.Workflow module
$workflowModulePath = Join-Path $Global:ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psd1'

Import-Module $workflowModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.Workflow module imported'

# Execute main workflow
Start-IPAPWorkflow
