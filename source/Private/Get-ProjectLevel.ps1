<#
.SYNOPSIS
    计算项目的统一等级
.DESCRIPTION
    纯函数：把有文字图与无文字图的单图分级结果归并成「项目统一等级」。
    同一项目内所有图片必须使用同一个 Level，否则被放大的页面宽高会与未放大的页面不一致
    （FFmpeg 放大 1.2 倍、Real-CUGAN 放大 2 倍），后续嵌字无法对齐。

    归并规则：
    - 以有文字图的多数等级为准；没有有文字图时退化为用无文字图的多数等级；
    - 平票时取较高等级（宁可多放大，不欠放大）；
    - 无文字图自身的等级不参与投票，只能跟随有文字图的结果。

    典型场景：731 页项目里有文字图 729 张判 Level 0、2 张判 Level 1，
    多数等级为 Level 0，于是整个项目按 Level 0 处理，无文字图即使单图判 Level 2 也不放大。
.PARAMETER TextLevels
    有文字图的单图等级集合，每个元素为 0/1/2。允许为空集合（全部页面都是无文字图）。
.PARAMETER NonTextLevels
    无文字图的单图等级集合，每个元素为 0/1/2。仅当 TextLevels 为空时作为定级依据。
.EXAMPLE
    Get-ProjectLevel -TextLevels @(0, 0, 1) -NonTextLevels @(2)
    有文字图多数为 Level 0，返回 0（无文字图的 Level 2 被压制）。
.EXAMPLE
    Get-ProjectLevel -TextLevels @(1, 2) -NonTextLevels @()
    两张有文字图一票对一票，平票取高，返回 2。
.INPUTS
    无
.OUTPUTS
    System.Int32（0/1/2）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-ProjectLevel {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [int[]]$TextLevels,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [int[]]$NonTextLevels = @()
    )

    # 基准集合：有文字图是主内容且页数占绝对多数，优先用它定级；全部为无文字图时退化
    [int[]]$ReferenceLevels = @($TextLevels).Count -gt 0 ? $TextLevels : $NonTextLevels

    if (@($ReferenceLevels).Count -eq 0) {
        $ErrorMessage = '分级结果为空，无法确定项目统一等级'
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    # 参数契约：等级只能是 0/1/2，越界视为调用方 bug，不做静默修正
    foreach ($LevelValue in $ReferenceLevels) {
        if ($LevelValue -lt 0 -or $LevelValue -gt 2) {
            $ErrorMessage = "分级结果包含非法等级: $LevelValue（有效值 0/1/2）"
            Write-LogEntry -Level Error -Message $ErrorMessage
            throw [System.ArgumentException]::new($ErrorMessage)
        }
    }

    # 多数票：按出现次数降序分组，保留次数最高的所有组，再从中取较高等级
    [object[]]$Groups = @($ReferenceLevels | Group-Object | Sort-Object -Property Count -Descending)
    [int]$MaxCount = [int]$Groups[0].Count
    [int[]]$TopLevels = @(
        $Groups | Where-Object { [int]$PSItem.Count -eq $MaxCount } | ForEach-Object { [int]$PSItem.Name }
    )
    [int]$ProjectLevel = [int]($TopLevels | Measure-Object -Maximum).Maximum

    return $ProjectLevel
}
