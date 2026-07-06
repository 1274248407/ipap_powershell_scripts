<#
.SYNOPSIS
    IPAP 工作流项目管理模块
.DESCRIPTION
    提供项目目录结构创建、README 文件生成和翻译文件管理功能。
#>

# ProjectManager 模块依赖 IPAP.Core，IPAP.Core 由 Main.ps1 统一导入
# 不需要重复导入 PoShLog 和 IPAP.Core

<#
.SYNOPSIS
    创建项目目录结构
.DESCRIPTION
    创建符合 IPAP 工作流标准的项目目录结构，包括预处理和排版目录。
    若目录已存在则询问用户是否覆盖，创建失败时记录错误日志。
    在项目目录下创建子目录：
    '02_Preprocessing\raw_source',
    '02_Preprocessing\original_non_text_raw',
    '02_Preprocessing\inpainted',
    '02_Preprocessing\mask',
    '03_Typesetting\workfiles',
    '03_Typesetting\final_pages'
.PARAMETER BaseDir
    (string, Mandatory) 项目基础目录。
    （适用于所有参数集）
.PARAMETER ProjectName
    (string, Mandatory) 项目名称。
    （适用于所有参数集）
.EXAMPLE
    New-ProjectStructure -BaseDir "C:\Projects" -ProjectName "Manga1"
    在 C:\Projects 目录下创建名为 2026-04-20_Manga1 的项目目录。
.INPUTS
    无
.OUTPUTS
    string 或 $null (创建成功时返回项目目录路径)
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function New-ProjectStructure
{
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseDir,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,
        [switch]$Force
    )

    # 构建项目目录路径
    $today = Get-Date -Format 'yyyy-MM-dd'
    $projectDirName = "${today}_${ProjectName}"
    $projectDir = Join-Path -Path $BaseDir -ChildPath $projectDirName

    # 使用 -LiteralPath 处理包含特殊字符的路径
    if (Test-Path -LiteralPath $projectDir)
    {
        # 当 -Force 指定时跳过确认提示
        if (-not $Force -and -not $PSCmdlet.ShouldContinue('项目目录已存在，是否覆盖现有目录？', '确认操作'))
        {
            Write-InfoLog '用户取消覆盖操作'
            return $null
        }
    }

    if ($PSCmdlet.ShouldProcess($projectDir, '创建项目目录结构'))
    {
        try
        {
            Write-InfoLog "正在创建项目目录: $projectDir"

            New-Item -ItemType Directory -Path $projectDir -Force | Out-Null

            $subDirs = @(
                '02_Preprocessing\raw_source',
                '02_Preprocessing\original_non_text_raw',
                '02_Preprocessing\inpainted',
                '02_Preprocessing\mask',
                '03_Typesetting\workfiles',
                '03_Typesetting\final_pages'
            )

            foreach ($subDir in $subDirs)
            {
                $fullPath = Join-Path $projectDir $subDir
                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                Write-InfoLog "已创建子目录: $fullPath"
            }

            Write-InfoLog '项目目录结构创建成功'
            return $projectDir
        }
        catch
        {
            Write-ErrorLog "创建项目目录失败: $($PSItem.Exception.Message)"
            return $null
        }
    }
}

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
                return
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

<#
.SYNOPSIS
    提示用户输入项目相关的多行信息并格式化
.DESCRIPTION
    提示用户输入项目名称、作品中文译名和原文项目简介以及中文项目简介，
    然后将这些信息按照特定模板格式化为一个字符串，并返回格式化后的
    字符串和项目名称。
.EXAMPLE
    Get-ProjectBriefInfo
    获取项目简介信息并返回格式化后的字符串和项目名称。
.INPUTS
    无
.OUTPUTS
    object[] (包含格式化字符串和项目名称)
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Read-MultiLineInput
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param (
        [string]$Prompt
    )

    [array]$lines = @()
    # 创建一个"字符串构建器"。在循环中频繁修改字符串时，使用 StringBuilder 比直接用 += 拼接字符串性能更高。
    [System.Text.StringBuilder]$currentLine = [System.Text.StringBuilder]::new()

    if ($Prompt)
    {
        Write-Host $Prompt
    }

    while ($true)
    {
        $key = [Console]::ReadKey($true)

        # 检查是否按下了 Ctrl 修饰键
        if ($key.Modifiers -band [ConsoleModifiers]::Control)
        {
            # 且同时按下了 D（[char]4 是终端中 Ctrl+D 的控制字符），则退出循环
            if ($key.KeyChar -eq [char]4 -or $key.KeyChar -eq [char]'d')
            {
                if ($currentLine.Length -gt 0)
                {
                    $lines += $currentLine.ToString()
                }
                break
            }
        }

        switch ($key.Key)
        {
            # 将当前行存入 $lines 数组，清空 $currentLine 准备接收下一行，并换行显示。
            { $PSItem -eq [ConsoleKey]::Enter }
            {
                $lines += $currentLine.ToString()
                $currentLine.Clear()
                Write-Host
            }
            # 如果当前行有字符，将长度减 1（删除最后一个字符）。 `b `b 是在控制台把光标往回退一格并覆盖原字符，实现视觉上的删除。
            { $PSItem -eq [ConsoleKey]::Backspace }
            {
                if ($currentLine.Length -gt 0)
                {
                    $currentLine.Length = $currentLine.Length - 1
                    Write-Host "`b `b" -NoNewline
                }
            }
            # 直接清空当前行所有内容。通过打印 80 个空格覆盖原内容，再重新打印提示语和清空后的当前行。
            { $PSItem -eq [ConsoleKey]::Delete }
            {
                if ($currentLine.Length -gt 0)
                {
                    # 保存当前长度用于清除屏幕
                    $clearLength = $currentLine.Length + $Prompt.Length
                    $currentLine.Clear()
                    # 动态生成所需数量的空格
                    $spaces = ' ' * $clearLength
                    Write-Host "`r$spaces`r" -NoNewline
                    Write-Host $Prompt -NoNewline
                    Write-Host $currentLine.ToString() -NoNewline
                }
            }
            # 如果是可打印字符（ASCII 码大于空格），追加到 $currentLine，
            # 并用 Write-Host 显示在屏幕上。[void] 用于忽略 Append 方法的返回值
            default
            {
                if ($key.KeyChar -and $key.KeyChar -ge ' ')
                {
                    [void]$currentLine.Append($key.KeyChar)
                    Write-Host $key.KeyChar -NoNewline
                }
            }
        }
    }

    return $lines
}
<#
.SYNOPSIS
    获取项目信息并生成格式化的项目简介模板。
.DESCRIPTION
    通过交互式输入或直接传参获取作者名、原作品名、中文译名、原文简介和中文简介，
    然后生成格式化的项目信息字符串。此函数支持混合使用两种方式：
    已提供值的参数将跳过交互式输入，仅对未提供的参数进行提示。
.PARAMETER Author
    作者名，用于构建项目标识。
.PARAMETER OriginalTitle
    原作品名（原文），用于构建项目标识。
.PARAMETER ChineseTitle
    作品的中文译名，用于构建中文项目标识。
.PARAMETER OriginalOverview
    作品的原文简介内容。如为多行，请使用换行符分隔。
.PARAMETER ChineseOverview
    作品的中文简介内容。如为多行，请使用换行符分隔。
.EXAMPLE
    Get-ProjectBriefInfo
    纯交互式调用，函数将通过提示依次询问各参数值。
.EXAMPLE
    Get-ProjectBriefInfo -Author "鲁迅" -OriginalTitle "呐喊" -ChineseTitle "呐喊"
    仅传部分参数，未传参数将通过交互式输入获取。
.EXAMPLE
    Get-ProjectBriefInfo -Author "Author" -OriginalTitle "Title" -ChineseTitle "标题" -OriginalOverview "Original`nOverview" -ChineseOverview "中文`n简介"
    全部参数直接传入，函数直接生成格式化输出，不触发任何交互式输入。
.INPUTS
    System.String
.OUTPUTS
    System.String, System.String（返回一个包含格式化文本和项目名的元组）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-ProjectBriefInfo
{
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()]
        [System.String]
        $Author,

        [Parameter()]
        [System.String]
        $OriginalTitle,

        [Parameter()]
        [System.String]
        $ChineseTitle,

        [Parameter()]
        [System.String]
        $OriginalOverview,

        [Parameter()]
        [System.String]
        $ChineseOverview
    )

    Write-InfoLog '=== 项目信息输入 ==='

    # 输入作者名（参数为空时交互式获取）
    if ([System.String]::IsNullOrWhiteSpace($Author))
    {
        $Author = Read-Host '作者名'
        $Author = $Author.Trim()
    }

    # 输入原作品名（原文）（参数为空时交互式获取）
    if ([System.String]::IsNullOrWhiteSpace($OriginalTitle))
    {
        $OriginalTitle = Read-Host '原作品名（原文）'
        $OriginalTitle = $OriginalTitle.Trim()
    }

    # 输入作品中文译名（参数为空时交互式获取）
    if ([System.String]::IsNullOrWhiteSpace($ChineseTitle))
    {
        $ChineseTitle = Read-Host '作品中文译名'
        $ChineseTitle = $ChineseTitle.Trim()
    }

    # 自动组合 projectName 和 authorChinese
    $projectName = "[${Author}] ${OriginalTitle}"
    $authorChinese = "[${Author}] ${ChineseTitle}"

    # 输入原文简介（参数为空时交互式获取）
    if ([System.String]::IsNullOrWhiteSpace($OriginalOverview))
    {
        $originalOverviewLines = Read-MultiLineInput -Prompt '请输入【原文简介】（按 Ctrl+D 结束）：'
        $OriginalOverview = $originalOverviewLines -join "`n"
    }

    # 输入中文简介（参数为空时交互式获取）
    if ([System.String]::IsNullOrWhiteSpace($ChineseOverview))
    {
        $chineseOverviewLines = Read-MultiLineInput -Prompt '请输入【中文简介】（按 Ctrl+D 结束）：'
        $ChineseOverview = $chineseOverviewLines -join "`n"
    }

    # 构建格式化的 tpl
    $tpl = @(
        '',
        '【项目名称】',
        "  原文：$projectName",
        "  中文：$authorChinese",
        '',
        '【项目简介】',
        '---',
        '【原文简介】',
        $OriginalOverview,
        '---',
        '【中文简介】',
        $ChineseOverview,
        '---',
        ''
    )

    $formatted = $tpl -join "`n"

    return $formatted, $projectName
}

Export-ModuleMember -Function @(
    'New-ProjectStructure',
    'New-ReadmeFile',
    'Get-ProjectBriefInfo',
    'Read-MultiLineInput'
)
