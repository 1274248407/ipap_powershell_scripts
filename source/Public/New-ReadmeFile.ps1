<#
.SYNOPSIS
    创建 README.md 文件
.DESCRIPTION
    根据项目配置、当日日期与图片分级结果生成 README.md，包含项目基本信息、进度跟踪与处理笔记模板。
    项目基本信息中的张数、统一等级与放大倍数全部由分级结果派生，不再由调用方另传一份可能失真的值。
    预处理详情段只列「单图等级与项目统一等级不一致」的页面，并给出各类别的张数与长边 / YDIF 范围，
    避免整批页面被逐行列成表格（731 页项目会产出 750 行噪声）。
    创建失败时记录错误日志并抛出强类型异常。
.PARAMETER ProjectDir
    (string, Mandatory) 项目根目录路径。
.PARAMETER ProjectName
    (string, Mandatory) 项目名称。
.PARAMETER ProjectLevel
    (int, Mandatory) 项目统一等级（0/1/2），由 Get-ProjectLevel 归并得到。
.PARAMETER TextImageLevels
    (array) 有文字图的分级结果（可选），每个对象应包含 Image、Level、LongEdge、YDIF 属性。
.PARAMETER NonTextImageLevels
    (array) 无文字图的分级结果（可选），每个对象应包含 Image、Level、LongEdge、YDIF 属性。
.PARAMETER RealCuganScale
    (int) Real-CUGAN 的放大倍数，仅用于 Level 2 的文案，默认 2。
.PARAMETER BriefText
    (string) 项目简介文本（可选），若提供则写入 README.md 的项目简介段落。
.EXAMPLE
    New-ReadmeFile -ProjectDir 'C:\Projects\Manga1' -ProjectName 'Manga1' -ProjectLevel 1 -TextImageLevels $textLevels
    按 Level 1 生成 README.md。
.EXAMPLE
    New-ReadmeFile -ProjectDir 'C:\Projects\Manga1' -ProjectName 'Manga1' -ProjectLevel 0 -TextImageLevels $t -NonTextImageLevels $nt -BriefText '项目简介'
    生成 Level 0 项目的 README.md，并附带项目简介。
.INPUTS
    无
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>

function New-ReadmeFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2)]
        [int]$ProjectLevel,
        [AllowEmptyCollection()]
        [array]$TextImageLevels = @(),
        [AllowEmptyCollection()]
        [array]$NonTextImageLevels = @(),
        [ValidateRange(1, 4)]
        [int]$RealCuganScale = 2,
        [string]$BriefText = $null
    )

    $readmePath = Join-Path $ProjectDir 'README.md'

    if ($PSCmdlet.ShouldProcess($readmePath, '创建 README.md 文件')) {
        $today = Get-Date -Format 'yyyy-MM-dd'

        # 全部派生量只在这里算一次，避免调用方与模板各写一份而互相矛盾
        [int]$TextCount = @($TextImageLevels).Count
        [int]$NonTextCount = @($NonTextImageLevels).Count
        [int]$TotalCount = $TextCount + $NonTextCount
        [string]$ProjectLevelText = Format-ProjectLevelText -Level $ProjectLevel -RealCuganScale $RealCuganScale
        [string]$upscaleStatus = $ProjectLevel -gt 0 ? 'X' : ' '
        [string]$upscaleRatioText = switch ($ProjectLevel) {
            0 { 'N/A' }
            1 { '1.2' }
            default { "$RealCuganScale" }
        }

        # 构建项目简介段落
        $briefSection = ''
        if ($BriefText) {
            $briefSection = @"

## 项目信息
$BriefText
"@
        }

        # 构建预处理详情段：只列与项目等级不一致的页面
        $detailSection = ''
        if ($TotalCount -gt 0) {
            $detailLines = [System.Text.StringBuilder]::new()
            [void]$detailLines.AppendLine()
            [void]$detailLines.AppendLine('## 预处理详情')
            [void]$detailLines.AppendLine()

            if ($TextCount -gt 0) {
                [void]$detailLines.AppendLine("- 有文字图: $(Format-LevelSummaryText -Levels $TextImageLevels)")
            }
            if ($NonTextCount -gt 0) {
                [void]$detailLines.AppendLine("- 无文字图: $(Format-LevelSummaryText -Levels $NonTextImageLevels)")
            }

            # 异类页：单图等级与项目统一等级不同，需要人工复核「为什么没按它的等级处理」
            $outliers = @(
                foreach ($level in @($TextImageLevels)) {
                    if ([int]$level.Level -ne $ProjectLevel) {
                        [PSCustomObject]@{ Level = $level; Category = '有文字图' }
                    }
                }
                foreach ($level in @($NonTextImageLevels)) {
                    if ([int]$level.Level -ne $ProjectLevel) {
                        [PSCustomObject]@{ Level = $level; Category = '无文字图' }
                    }
                }
            )

            if ($outliers.Count -gt 0) {
                [void]$detailLines.AppendLine()
                [void]$detailLines.AppendLine("### 与项目等级不一致的页面（$($outliers.Count) 张）")
                [void]$detailLines.AppendLine()
                [void]$detailLines.AppendLine('| 文件名 | 类别 | 单图等级 | 长边 | YDIF |')
                [void]$detailLines.AppendLine('|--------|------|----------|------|------|')
                foreach ($outlier in $outliers) {
                    $fileName = [System.IO.Path]::GetFileName($outlier.Level.Image.FullName)
                    [void]$detailLines.AppendLine("| $fileName | $($outlier.Category) | Level $($outlier.Level.Level) | $($outlier.Level.LongEdge)px | $($outlier.Level.YDIF) |")
                }
            }

            $detailSection = $detailLines.ToString()
        }

        $content = @"
# 项目记录: ${ProjectName} (${today})

## 项目基本信息
- 有文字图: ${TextCount} 张
- 无文字图: ${NonTextCount} 张
- 合计: ${TotalCount} 张
- 项目统一等级: ${ProjectLevelText}
- 原始文件是否需要高清化: [${upscaleStatus}]
- 使用高清化倍数: ${upscaleRatioText}
${detailSection}
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

        try {
            $readmePath = Join-Path $ProjectDir 'README.md'
            Write-LogEntry -Level Info -Message "正在写入 README.md 文件到 $readmePath"

            # 确保项目目录存在（使用 -LiteralPath 处理特殊字符）
            if (-not (Test-Path -LiteralPath $ProjectDir)) {
                # 记录错误现场后显式抛出强类型异常（Write-LogEntry 为纯日志函数）
                $ErrorMessage = "项目目录不存在: $ProjectDir"
                Write-LogEntry -Level Error -Message $ErrorMessage
                throw [System.ArgumentException]::new($ErrorMessage)
            }

            # 使用 Out-File -LiteralPath 写入文件，避免 PowerShell 通配符问题
            $content | Out-File -LiteralPath $readmePath -Encoding utf8 -NoNewline

            if (Test-Path -LiteralPath $readmePath) {
                Write-LogEntry -Level Info -Message 'README.md 文件创建/覆盖成功'
            }
            else {
                # 记录错误现场后显式抛出强类型异常（Write-LogEntry 为纯日志函数）
                $ErrorMessage = '无法验证 README.md 文件创建'
                Write-LogEntry -Level Error -Message $ErrorMessage
                throw [System.InvalidOperationException]::new($ErrorMessage)
            }
        }
        catch {
            # 记录上下文后抛出包装异常并保留 InnerException（禁止吞异常）
            Write-LogEntry -Level Error -Message "创建/覆盖 README.md 文件失败: $($PSItem.Exception.Message)"
            throw [System.IO.IOException]::new("创建/覆盖 README.md 文件失败: $($PSItem.Exception.Message)", $PSItem.Exception)
        }
    }
}
