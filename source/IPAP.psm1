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

# 模块级配置实例（跨函数共享，使用 script: 作用域避免全局污染）
$script:IPAPConfigInstance = $null

# 加载顺序：类 -> 私有函数 -> 公开函数（依赖顺序，不可调换）
$loadOrder = @('Classes', 'Private', 'Public')

foreach ($folder in $loadOrder) {
    # 构建子目录路径
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    if (-not (Test-Path -LiteralPath $folderPath)) {
        continue
    }

    # 遍历并 dot-source 所有 .ps1 文件
    Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | ForEach-Object {
        # dot-source 当前源文件
        . $PSItem.FullName
    }
}

$moduleLoadStart.Stop()

# PSToml 是硬依赖：必须在这里导入一次，才能被模块内所有函数看见。
# 不能指望 Get-Configuration 里的 Import-Module -Scope Local——它只活在类方法自己的作用域里，
# 方法返回后 ConvertFrom-Toml 就从模块中消失（v3.0.0 的发布包正是因此读不回 README.toml）。
[string]$TomlPackageRoot = Split-Path -Path $PSScriptRoot -Parent
foreach ($TomlCandidate in @(
        # 发布包：<pkg>\IPAP\RequiredModules 或 <pkg>\RequiredModules
        (Join-Path -Path $PSScriptRoot -ChildPath 'RequiredModules\PSToml'),
        (Join-Path -Path $TomlPackageRoot -ChildPath 'RequiredModules\PSToml'),
        # 开发仓库：<repo>\output\RequiredModules
        (Join-Path -Path $TomlPackageRoot -ChildPath 'output\RequiredModules\PSToml')
    )) {
    if (-not (Test-Path -LiteralPath $TomlCandidate -PathType Container)) {
        continue
    }
    try {
        # 不带 -Scope：在模块脚本里导入即落在模块作用域，调用方作用域不受污染
        Import-Module $TomlCandidate -Force -ErrorAction Stop
        break
    }
    catch {
        Write-Verbose "PSToml 导入失败，跳过候选路径: $TomlCandidate"
    }
}

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
    'Get-ImageInfo',
    'Get-ImageLevel',
    'Invoke-ParallelUpscale',
    'New-ProjectStructure',
    'New-ReadmeFile',
    'Read-MultiLineInput',
    'Get-ProjectBriefInfo',
    'Start-IPAPWorkflow',
    'Select-NonTextImage',
    'Test-UpscaleResult',
    'Write-LogEntry'
)
