<#
.SYNOPSIS
    创建 README.md 文件
.DESCRIPTION
    根据项目配置和日期信息生成 README.md 文件，包含项目基本信息、进度跟踪和处理笔记等模板内容。
    可选地包含高清化处理详情（Level 1 和 Level 2 的图片列表及分析数据）。
    创建失败时记录错误日志。
.PARAMETER ProjectDir
    (string, Mandatory) 项目根目录路径。
.PARAMETER ProjectName
    (string, Mandatory) 项目名称。
.PARAMETER ImageCount
    (int, Mandatory) 原始文件数量。
.PARAMETER NeedUpscale
    (bool, Mandatory) 是否需要高清化处理。
.PARAMETER UpscaleRatio
    (int) 高清化倍数，默认为 2。
.PARAMETER BriefText
    (string) 项目简介文本（可选），若提供则写入 README.md 的项目简介段落。
.PARAMETER Level1ImageLevels
    (array) Level 1 图片的分级信息（可选），每个对象应包含 Image、LongEdge、YDIF 属性。
.PARAMETER Level2ImageLevels
    (array) Level 2 图片的分级信息（可选），每个对象应包含 Image、LongEdge、YDIF 属性。
.PARAMETER NonTextLevel1ImageLevels
    (array) 无文字图 Level 1 分级信息（可选），每个对象应包含 Image、LongEdge、YDIF 属性。
.PARAMETER NonTextLevel2ImageLevels
    (array) 无文字图 Level 2 分级信息（可选），每个对象应包含 Image、LongEdge、YDIF 属性。
.EXAMPLE
    New-ReadmeFile -ProjectDir "C:\Projects\Manga1" -ProjectName "Manga1" -ImageCount 50 -NeedUpscale $true -UpscaleRatio 2
    在项目目录下创建包含高清化状态的 README.md 文件。
.EXAMPLE
    New-ReadmeFile -ProjectDir "C:\Projects\Manga1" -ProjectName "Manga1" -ImageCount 50 -NeedUpscale $true -UpscaleRatio 2 -BriefText "项目简介内容"
    在 README.md 中同时包含项目简介内容。
.EXAMPLE
    New-ReadmeFile -ProjectDir "C:\Projects\Manga1" -ProjectName "Manga1" -ImageCount 50 -NeedUpscale $true -UpscaleRatio 2 -Level1ImageLevels $level1Levels -Level2ImageLevels $level2Levels -NonTextLevel1ImageLevels $nonTextL1 -NonTextLevel2ImageLevels $nonTextL2
    在 README.md 中包含有文字图和无文字图的高清化处理详情。
.INPUTS
    无
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>

function New-ReadmeFile
{
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,
        [Parameter(Mandatory = $true)]
        [int]$ImageCount,
        [Parameter(Mandatory = $true)]
        [bool]$NeedUpscale,
        [int]$UpscaleRatio = 2,
        [string]$BriefText = $null,
        [array]$Level1ImageLevels = @(),
        [array]$Level2ImageLevels = @(),
        [array]$NonTextLevel1ImageLevels = @(),
        [array]$NonTextLevel2ImageLevels = @()
    )

    $readmePath = Join-Path $ProjectDir 'README.md'

    if ($PSCmdlet.ShouldProcess($readmePath, '创建 README.md 文件'))
    {
        $today = Get-Date -Format 'yyyy-MM-dd'
        $upscaleStatus = if ($NeedUpscale)
        {
            'X'
        }
        else
        {
            ' '
        }
        $upscaleRatioText = if ($NeedUpscale)
        {
            $UpscaleRatio.ToString()
        }
        else
        {
            'N/A'
        }

        # 构建项目简介段落
        $briefSection = ''
        if ($BriefText)
        {
            $briefSection = @"

## 项目信息
$BriefText
"@
        }

        # 构建高清化详情段落
        $upscaleDetailSection = ''
        if ($Level1ImageLevels.Count -gt 0 -or $Level2ImageLevels.Count -gt 0 -or $NonTextLevel1ImageLevels.Count -gt 0 -or $NonTextLevel2ImageLevels.Count -gt 0)
        {
            $upscaleDetailLines = [System.Text.StringBuilder]::new()
            [void]$upscaleDetailLines.AppendLine()
            [void]$upscaleDetailLines.AppendLine('## 高清化处理详情')

            # 有文字图详情
            if ($Level1ImageLevels.Count -gt 0 -or $Level2ImageLevels.Count -gt 0)
            {
                [void]$upscaleDetailLines.AppendLine()
                [void]$upscaleDetailLines.AppendLine('### 有文字图')

                # Level 1 详情
                if ($Level1ImageLevels.Count -gt 0)
                {

                    [void]$upscaleDetailLines.AppendLine()
                    [void]$upscaleDetailLines.AppendLine("#### Level 1 (FFmpeg 锐化) - $($Level1ImageLevels.Count) 张")
                    [void]$upscaleDetailLines.AppendLine()
                    [void]$upscaleDetailLines.AppendLine('| 文件名 | 长边分辨率 | YDIF |')
                    [void]$upscaleDetailLines.AppendLine('|--------|-----------|------|')
                    foreach ($level in $Level1ImageLevels)
                    {
                        $fileName = [System.IO.Path]::GetFileName($level.Image.FullName)
                        [void]$upscaleDetailLines.AppendLine("| $fileName | $($level.LongEdge)px | $($level.YDIF) |")
                    }
                }

                # Level 2 详情
                if ($Level2ImageLevels.Count -gt 0)
                {
                    [void]$upscaleDetailLines.AppendLine()
                    [void]$upscaleDetailLines.AppendLine("#### Level 2 (Real-CUGAN AI 超分) - $($Level2ImageLevels.Count) 张")
                    [void]$upscaleDetailLines.AppendLine()
                    [void]$upscaleDetailLines.AppendLine('| 文件名 | 长边分辨率 | YDIF |')
                    [void]$upscaleDetailLines.AppendLine('|--------|-----------|------|')
                    foreach ($level in $Level2ImageLevels)
                    {
                        $fileName = [System.IO.Path]::GetFileName($level.Image.FullName)
                        [void]$upscaleDetailLines.AppendLine("| $fileName | $($level.LongEdge)px | $($level.YDIF) |")
                    }
                }
            }

            # 无文字图详情
            if ($NonTextLevel1ImageLevels.Count -gt 0 -or $NonTextLevel2ImageLevels.Count -gt 0)
            {
                [void]$upscaleDetailLines.AppendLine()
                [void]$upscaleDetailLines.AppendLine('### 无文字图')

                # 无文字图 Level 1 详情
                if ($NonTextLevel1ImageLevels.Count -gt 0)
                {
                    [void]$upscaleDetailLines.AppendLine()
                    [void]$upscaleDetailLines.AppendLine("#### Level 1 (FFmpeg 锐化) - $($NonTextLevel1ImageLevels.Count) 张")
                    [void]$upscaleDetailLines.AppendLine()
                    [void]$upscaleDetailLines.AppendLine('| 文件名 | 长边分辨率 | YDIF |')
                    [void]$upscaleDetailLines.AppendLine('|--------|-----------|------|')
                    foreach ($level in $NonTextLevel1ImageLevels)
                    {
                        $fileName = [System.IO.Path]::GetFileName($level.Image.FullName)
                        [void]$upscaleDetailLines.AppendLine("| $fileName | $($level.LongEdge)px | $($level.YDIF) |")
                    }
                }

                # 无文字图 Level 2 详情
                if ($NonTextLevel2ImageLevels.Count -gt 0)
                {
                    [void]$upscaleDetailLines.AppendLine()
                    [void]$upscaleDetailLines.AppendLine("#### Level 2 (Real-CUGAN AI 超分) - $($NonTextLevel2ImageLevels.Count) 张")
                    [void]$upscaleDetailLines.AppendLine()
                    [void]$upscaleDetailLines.AppendLine('| 文件名 | 长边分辨率 | YDIF |')
                    [void]$upscaleDetailLines.AppendLine('|--------|-----------|------|')
                    foreach ($level in $NonTextLevel2ImageLevels)
                    {
                        $fileName = [System.IO.Path]::GetFileName($level.Image.FullName)
                        [void]$upscaleDetailLines.AppendLine("| $fileName | $($level.LongEdge)px | $($level.YDIF) |")
                    }
                }
            }

            $upscaleDetailSection = $upscaleDetailLines.ToString()
        }

        $content = @"
# 项目记录: ${ProjectName} (${today})

## 项目基本信息
- 原始文件数量: ${ImageCount} 张
- 原始文件是否需要高清化: [${upscaleStatus}]
- 使用高清化倍数: ${upscaleRatioText}
${upscaleDetailSection}
## 进度跟踪
- [ ] 文件整理与分离
- [ ] OCR 处理与校对
- [ ] Inpainting 处理与修正
- [ ] 文本翻译
- [ ] 嵌字 (完成至页 X)
- [ ] 最终质量检查

## 处理笔记与特殊情况
### 预处理阶段

### 翻译阶段

### 嵌字阶段

## 待办/提醒

## 其他
- [任何你想记下的其他信息]
${briefSection}
"@

        try
        {
            $readmePath = Join-Path $ProjectDir 'README.md'
            Write-InfoLog "正在写入 README.md 文件到 $readmePath"

            # 确保项目目录存在（使用 -LiteralPath 处理特殊字符）
            if (-not (Test-Path -LiteralPath $ProjectDir))
            {
                Write-ErrorLog "项目目录不存在: $ProjectDir"
            }

            # 使用 Out-File -LiteralPath 写入文件，避免 PowerShell 通配符问题
            $content | Out-File -LiteralPath $readmePath -Encoding utf8

            if (Test-Path -LiteralPath $readmePath)
            {
                Write-InfoLog 'README.md 文件创建/覆盖成功'
            }
            else
            {
                Write-ErrorLog '无法验证 README.md 文件创建'
            }
        }
        catch
        {
            Write-ErrorLog "创建/覆盖 README.md 文件失败: $($PSItem.Exception.Message)"
        }
    }
}

