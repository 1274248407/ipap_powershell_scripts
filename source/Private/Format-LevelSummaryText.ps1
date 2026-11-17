<#
.SYNOPSIS
    把一组分级结果汇总成一行摘要
.DESCRIPTION
    纯函数：输出「N 张，长边 A–Bpx，YDIF X–Y」形式的摘要，用于 README 的预处理详情段。
    长边与 YDIF 相同时只写一个值，避免「1920–1920px」这种噪声。
.PARAMETER Levels
    分级结果数组，每个对象需包含 LongEdge 与 YDIF 属性。
.EXAMPLE
    Format-LevelSummaryText -Levels $textImageLevels
    返回 '731 张，长边 560–1920px，YDIF 10.94–286.9'。
.INPUTS
    无
.OUTPUTS
    System.String
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Format-LevelSummaryText {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Levels
    )

    [int]$count = @($Levels).Count
    if ($count -eq 0) {
        return '0 张'
    }

    [int[]]$longEdges = @($Levels | ForEach-Object { [int]$PSItem.LongEdge })
    [double[]]$ydifs = @($Levels | ForEach-Object { [double]$PSItem.YDIF })

    [int]$minEdge = [int]($longEdges | Measure-Object -Minimum).Minimum
    [int]$maxEdge = [int]($longEdges | Measure-Object -Maximum).Maximum
    [string]$edgeText = $minEdge -eq $maxEdge ? "${minEdge}px" : "$minEdge–${maxEdge}px"

    [double]$minYdif = [math]::Round([double]($ydifs | Measure-Object -Minimum).Minimum, 2)
    [double]$maxYdif = [math]::Round([double]($ydifs | Measure-Object -Maximum).Maximum, 2)
    # 用 InvariantCulture 格式化，避免小数点随系统区域设置变成逗号
    [string]$minYdifText = $minYdif.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
    [string]$maxYdifText = $maxYdif.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
    [string]$ydifText = $minYdif -eq $maxYdif ? $minYdifText : "$minYdifText–$maxYdifText"

    return "$count 张，长边 $edgeText，YDIF $ydifText"
}
