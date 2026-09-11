<#
.SYNOPSIS
    IPAP - 漫画翻译准备自动化工具启动脚本
.DESCRIPTION
    以双路径策略定位并导入 IPAP 统一模块：
    1. 开发模式：优先加载仓库内 source\IPAP.psd1（源码目录）
    2. 发布模式：回退加载发布包内 IPAP\IPAP.psd1（构建产物目录）
    随后初始化配置并启动主工作流。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

param()

# 校验 PowerShell 版本（本工具强依赖 PS7 新语法）
if ($PSVersionTable.PSVersion.Major -lt 7)
{
    Write-Error '错误: 需要 PowerShell 7 或更高版本'
    exit 1
}

# 设置控制台输出编码为 UTF-8，以支持特殊字符（如 ✓）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 按优先级构建模块清单候选路径：开发模式 source\ 优先，发布模式 IPAP\ 回退
$ManifestCandidates = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'source\IPAP.psd1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'IPAP\IPAP.psd1')
)

# 遍历候选路径，导入首个存在的模块清单
$IpapManifest = $null
foreach ($Candidate in $ManifestCandidates)
{
    # 找到首个存在的清单文件即导入
    if (Test-Path -LiteralPath $Candidate)
    {
        $IpapManifest = $Candidate
        break
    }
}

# 校验模块清单必须存在
if ($null -eq $IpapManifest)
{
    Write-Error '未找到 IPAP 模块清单（source\IPAP.psd1 或 IPAP\IPAP.psd1），请先运行 .\build.ps1 -Task Build'
    exit 1
}

# 导入 IPAP 统一模块
Import-Module -Name $IpapManifest -Force -Scope Global
Write-LogEntry -Level Success -Message "IPAP 模块已导入：$IpapManifest"

# 初始化配置（读取仓库根目录的 config.toml）
Get-Configuration -ProjectRoot $PSScriptRoot | Out-Null
Write-LogEntry -Level Success -Message 'IPAP 配置已初始化'

# 确认项目配置，获取用户确认后的配置实例并启动主工作流
$Config = Confirm-ProjectConfiguration
Start-IPAPWorkflow -Config $Config
