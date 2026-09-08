<#
.SYNOPSIS
    IPAP 统一模块加载器
.DESCRIPTION
    按 Classes -> Private -> Public 顺序 dot-source 加载全部源文件，
    并导出 Public 目录中定义的所有函数。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

# 记录加载耗时
$moduleLoadStart = [System.Diagnostics.Stopwatch]::StartNew()

# 全局配置实例（跨函数共享的模块级状态）
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
$Global:IPAPConfigInstance = $null

# 加载顺序：类 -> 私有函数 -> 公开函数（依赖顺序，不可调换）
$loadOrder = @('Classes', 'Private', 'Public')

foreach ($folder in $loadOrder)
{
    # 构建子目录路径
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    if (-not (Test-Path -LiteralPath $folderPath))
    {
        continue
    }

    # 遍历并 dot-source 所有 .ps1 文件
    Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | ForEach-Object {
        # dot-source 当前源文件
        . $PSItem.FullName
    }
}

$moduleLoadStart.Stop()
Write-Verbose "IPAP 模块加载完成，耗时 $($moduleLoadStart.ElapsedMilliseconds) ms"

# 导出全部公开函数
Export-ModuleMember -Function @(
    'Get-Configuration',
    'Reset-Configuration',
    'Test-ConfigurationInitialized',
    'Confirm-ProjectConfiguration',
    'Get-NaturalSortKey',
    'Get-FfmpegPath',
    'Get-FfprobePath',
    'Get-RealCuganExePath',
    'Get-SupportedImageFormat',
    'Test-SupportedImageFormat',
    'Get-AppConfiguration',
    'Get-PathConfiguration',
    'Get-ImageInfo',
    'Test-NeedUpscale',
    'Get-ImageLevel',
    'Invoke-ParallelUpscale',
    'Rename-FilesBySize',
    'New-ProjectStructure',
    'New-ReadmeFile',
    'Read-MultiLineInput',
    'Get-ProjectBriefInfo',
    'Start-IPAPWorkflow',
    'Select-NonTextImage',
    'Test-UpscaleResult'
)
