<#
.SYNOPSIS
    确认项目配置
.DESCRIPTION
    显示当前配置信息，询问用户是否应用配置。如果用户选择不应用，提供两种方式修改配置：使用文本编辑器或控制台直接输入。
    交互输入采用安全默认：仅显式 Y/y 视为应用；EOF/非交互环境保持当前配置不变。
    简介输入使用 Read-MultiLineInput，按 Ctrl+D 结束。
.PARAMETER Config
    IPAPConfiguration 实例（可选），如果未指定则使用全局配置实例。
.EXAMPLE
    # 显示配置并获取用户确认后的配置
    $config = Confirm-ProjectConfiguration
.INPUTS
    IPAPConfiguration
.OUTPUTS
    IPAPConfiguration
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Confirm-ProjectConfiguration {
    [CmdletBinding()]
    [OutputType('IPAPConfiguration')]
    param(
        [IPAPConfiguration]$Config = $null
    )

    if (-not $Config) {
        $Config = Get-Configuration
    }

    Write-LogEntry -Level Info -Message '--- 当前配置信息预览 ---'

    Write-LogEntry -Level Warning -Message '【路径配置】'
    Write-LogEntry -Level Info -Message "  项目根目录: $($Config.Paths.ProjectRoot)"
    Write-LogEntry -Level Info -Message "  基准项目目录: $($Config.Paths.BaseProjectDir ? $Config.Paths.BaseProjectDir : '[未配置]')"
    Write-LogEntry -Level Info -Message "  源图片目录: $($Config.Paths.SourceDir ? $Config.Paths.SourceDir : '[未配置]')"

    # 源目录体检：不存在 → 红；存在但无图片 → 黄；有图片 → 绿。只做提示，不中断流程
    if ($Config.Paths.SourceDir) {
        if (-not (Test-Path -LiteralPath $Config.Paths.SourceDir -PathType Container)) {
            Write-LogEntry -Level Error -Message "  源图片目录不存在: $($Config.Paths.SourceDir)"
        }
        else {
            [int]$SourceImageCount = @(
                Get-ChildItem -LiteralPath $Config.Paths.SourceDir -File |
                    Where-Object { Test-SupportedImageFormat -File $PSItem -SupportedFormats $Config.App.SupportedImageFormats }
            ).Count
            if ($SourceImageCount -eq 0) {
                Write-LogEntry -Level Warning -Message "  源图片目录中没有图片文件（支持格式: $($Config.App.SupportedImageFormats -join ' ')）"
            }
            else {
                Write-LogEntry -Level Success -Message "  源图片目录检测到 $SourceImageCount 张图片"
            }
        }
    }

    Write-LogEntry -Level Warning -Message '【项目信息】'
    Write-LogEntry -Level Info -Message "  作者: $($Config.Project.Author ? $Config.Project.Author : '[未配置]')"
    Write-LogEntry -Level Info -Message "  原作品名: $($Config.Project.OriginalTitle ? $Config.Project.OriginalTitle : '[未配置]')"
    Write-LogEntry -Level Info -Message "  中文译名: $($Config.Project.ChineseTitle ? $Config.Project.ChineseTitle : '[未配置]')"
    Write-LogEntry -Level Info -Message "  原文简介: $($Config.Project.OriginalOverview ? '已配置' : '[未配置]')"
    Write-LogEntry -Level Info -Message "  中文简介: $($Config.Project.ChineseOverview ? '已配置' : '[未配置]')"

    Write-LogEntry -Level Warning -Message '【应用配置】'
    Write-LogEntry -Level Info -Message "  最大工作线程数: $($Config.App.MaxWorkers)"
    Write-LogEntry -Level Info -Message "  Real-CUGAN 放大倍数: $($Config.App.UpscaleRatio)（FFmpeg 路径固定 1.2 倍）"
    Write-LogEntry -Level Info -Message "  模型选择: $($Config.App.ModelSelect)"

    # 安全默认：仅显式 Y/y 视为应用；回车、EOF 与其它任何输入一律视为不应用
    $response = Read-Host '是否应用当前配置？(Y/N)'
    # 非交互环境（stdin 结束）：直接返回当前配置，避免旧实现的死循环
    if ([string]::IsNullOrWhiteSpace($response)) {
        Write-LogEntry -Level Warning -Message '未读到输入（非交互环境），保持当前配置不变'
        return $Config
    }
    if (([string]$response).Trim() -in @('Y', 'y')) {
        Write-LogEntry -Level Info -Message '应用当前配置'
        return $Config
    }

    Write-LogEntry -Level Warning -Message '您选择不应用当前配置，请选择修改方式：'
    Write-LogEntry -Level Info -Message '  1) 使用文本编辑器修改 config.toml（推荐）'
    Write-LogEntry -Level Info -Message '  2) 在控制台直接输入'

    # 安全默认：仅显式 1 打开编辑器；EOF 直接返回，其它值按控制台输入处理
    $choice = Read-Host '请选择 (1/2)'
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-LogEntry -Level Warning -Message '未读到输入（非交互环境），保持当前配置不变'
        return $Config
    }

    if (([string]$choice).Trim() -eq '1') {
        Write-LogEntry -Level Info -Message '正在打开配置文件...'
        try {
            Start-Process -FilePath $Config.Paths.ConfigPath
            Write-LogEntry -Level Info -Message '配置文件已打开，请修改后保存。'
            $null = Read-Host '按 Enter 键继续...'
        }
        catch {
            # 打开配置文件失败属于可恢复场景：提示用户手动打开后继续流程
            Write-LogEntry -Level Warning -Message "无法自动打开配置文件，请手动打开: $($Config.Paths.ConfigPath)"
            $null = Read-Host '按 Enter 键继续...'
        }

        # 重置前保存 ProjectRoot，避免重置后无法恢复
        $projectRoot = $Config.Paths.ProjectRoot
        Reset-Configuration
        $Config = Get-Configuration -ProjectRoot $projectRoot
        return Confirm-ProjectConfiguration -Config $Config
    }
    else {
        Write-LogEntry -Level Warning -Message '请在控制台输入配置信息：'

        Write-LogEntry -Level Warning -Message '【路径配置】'
        $newSourceDir = Read-Host "源图片目录 [当前: $($Config.Paths.SourceDir)]"
        if ($newSourceDir) {
            $Config.Paths.SourceDir = $newSourceDir
        }

        Write-LogEntry -Level Warning -Message '【项目信息】'
        $newAuthor = Read-Host "作者 [当前: $($Config.Project.Author)]"
        if ($newAuthor) {
            $Config.Project.Author = $newAuthor
        }

        $newOriginalTitle = Read-Host "原作品名 [当前: $($Config.Project.OriginalTitle)]"
        if ($newOriginalTitle) {
            $Config.Project.OriginalTitle = $newOriginalTitle
        }

        $newChineseTitle = Read-Host "中文译名 [当前: $($Config.Project.ChineseTitle)]"
        if ($newChineseTitle) {
            $Config.Project.ChineseTitle = $newChineseTitle
        }

        # 多行输入复用 Read-MultiLineInput（Ctrl+D 结束），便于单元测试 Mock
        $newOriginalOverviewLines = @(Read-MultiLineInput -Prompt '原文简介（Ctrl+D 结束输入）')
        if ($newOriginalOverviewLines.Count -gt 0) {
            $Config.Project.OriginalOverview = $newOriginalOverviewLines -join "`n"
        }

        # 多行输入复用 Read-MultiLineInput（Ctrl+D 结束），便于单元测试 Mock
        $newChineseOverviewLines = @(Read-MultiLineInput -Prompt '中文简介（Ctrl+D 结束输入）')
        if ($newChineseOverviewLines.Count -gt 0) {
            $Config.Project.ChineseOverview = $newChineseOverviewLines -join "`n"
        }

        return Confirm-ProjectConfiguration -Config $Config
    }
}

