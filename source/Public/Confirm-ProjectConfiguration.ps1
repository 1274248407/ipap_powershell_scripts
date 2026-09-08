<#
.SYNOPSIS
    确认项目配置
.DESCRIPTION
    显示当前配置信息，询问用户是否应用配置。如果用户选择不应用，提供两种方式修改配置：使用文本编辑器或控制台直接输入。
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

function Confirm-ProjectConfiguration
{
    [CmdletBinding()]
    [OutputType('IPAPConfiguration')]
    param(
        [IPAPConfiguration]$Config = $null
    )

    if (-not $Config)
    {
        $Config = Get-Configuration
    }

    Write-LogEntry -Level Info -Message '--- 当前配置信息预览 ---'

    Write-LogEntry -Level Warning -Message '【路径配置】'
    Write-LogEntry -Level Info -Message "  项目根目录: $($Config.Paths.ProjectRoot)"
    Write-LogEntry -Level Info -Message "  基准项目目录: $(if ($Config.Paths.BaseProjectDir) { $Config.Paths.BaseProjectDir } else { '[未配置]' })"
    Write-LogEntry -Level Info -Message "  源图片目录: $(if ($Config.Paths.SourceDir) { $Config.Paths.SourceDir } else { '[未配置]' })"

    Write-LogEntry -Level Warning -Message '【项目信息】'
    Write-LogEntry -Level Info -Message "  作者: $(if ($Config.Project.Author) { $Config.Project.Author } else { '[未配置]' })"
    Write-LogEntry -Level Info -Message "  原作品名: $(if ($Config.Project.OriginalTitle) { $Config.Project.OriginalTitle } else { '[未配置]' })"
    Write-LogEntry -Level Info -Message "  中文译名: $(if ($Config.Project.ChineseTitle) { $Config.Project.ChineseTitle } else { '[未配置]' })"
    Write-LogEntry -Level Info -Message "  原文简介: $(if ($Config.Project.OriginalOverview) { '已配置' } else { '[未配置]' })"
    Write-LogEntry -Level Info -Message "  中文简介: $(if ($Config.Project.ChineseOverview) { '已配置' } else { '[未配置]' })"

    Write-LogEntry -Level Warning -Message '【应用配置】'
    Write-LogEntry -Level Info -Message "  最大工作线程数: $($Config.App.MaxWorkers)"
    Write-LogEntry -Level Info -Message "  放大倍数: $($Config.App.UpscaleRatio)"
    Write-LogEntry -Level Info -Message "  模型选择: $($Config.App.ModelSelect)"

    do
    {
        $response = Read-Host '是否应用当前配置？(Y/N)'
    } while ($response -ne 'Y' -and $response -ne 'y' -and $response -ne 'N' -and $response -ne 'n')

    if ($response -eq 'Y' -or $response -eq 'y')
    {
        Write-LogEntry -Level Info -Message '应用当前配置'
        return $Config
    }

    Write-LogEntry -Level Warning -Message '您选择不应用当前配置，请选择修改方式：'
    Write-LogEntry -Level Info -Message '  1) 使用文本编辑器修改 config.toml（推荐）'
    Write-LogEntry -Level Info -Message '  2) 在控制台直接输入'

    do
    {
        $choice = Read-Host '请选择 (1/2)'
    } while ($choice -ne '1' -and $choice -ne '2')

    if ($choice -eq '1')
    {
        Write-LogEntry -Level Info -Message '正在打开配置文件...'
        try
        {
            Start-Process -FilePath $Config.Paths.ConfigPath
            Write-LogEntry -Level Info -Message '配置文件已打开，请修改后保存。'
            $null = Read-Host '按 Enter 键继续...'
        }
        catch
        {
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
    else
    {
        Write-LogEntry -Level Warning -Message '请在控制台输入配置信息：'

        Write-LogEntry -Level Warning -Message '【路径配置】'
        $newSourceDir = Read-Host "源图片目录 [当前: $($Config.Paths.SourceDir)]"
        if ($newSourceDir)
        {
            $Config.Paths.SourceDir = $newSourceDir
        }

        Write-LogEntry -Level Warning -Message '【项目信息】'
        $newAuthor = Read-Host "作者 [当前: $($Config.Project.Author)]"
        if ($newAuthor)
        {
            $Config.Project.Author = $newAuthor
        }

        $newOriginalTitle = Read-Host "原作品名 [当前: $($Config.Project.OriginalTitle)]"
        if ($newOriginalTitle)
        {
            $Config.Project.OriginalTitle = $newOriginalTitle
        }

        $newChineseTitle = Read-Host "中文译名 [当前: $($Config.Project.ChineseTitle)]"
        if ($newChineseTitle)
        {
            $Config.Project.ChineseTitle = $newChineseTitle
        }

        Write-LogEntry -Level Warning -Message '原文简介（每行输入后按 Enter，输入空行结束）：'
        $newOriginalOverviewLines = @()
        while ($true)
        {
            # ReadLine 返回空字符串（用户输入空行）或 $null（EOF：Windows 下为 Ctrl+Z 后按 Enter）时结束输入
            $line = $host.ui.ReadLine()
            if (-not $line)
            {
                break
            }
            $newOriginalOverviewLines += $line
        }
        if ($newOriginalOverviewLines.Count -gt 0)
        {
            $Config.Project.OriginalOverview = $newOriginalOverviewLines -join "`n"
        }

        Write-LogEntry -Level Warning -Message '中文简介（每行输入后按 Enter，输入空行结束）：'
        $newChineseOverviewLines = @()
        while ($true)
        {
            # ReadLine 返回空字符串（用户输入空行）或 $null（EOF：Windows 下为 Ctrl+Z 后按 Enter）时结束输入
            $line = $host.ui.ReadLine()
            if (-not $line)
            {
                break
            }
            $newChineseOverviewLines += $line
        }
        if ($newChineseOverviewLines.Count -gt 0)
        {
            $Config.Project.ChineseOverview = $newChineseOverviewLines -join "`n"
        }

        return Confirm-ProjectConfiguration -Config $Config
    }
}

