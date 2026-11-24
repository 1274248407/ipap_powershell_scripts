<#
.SYNOPSIS
    判断一段文本是否更接近中文而不是日文
.DESCRIPTION
    纯函数：按字符类别做启发式判定，用于「中文字段里填的其实是原文」这种情况。

    判定规则：
    1. 没有汉字 → 不是中文（纯英文、纯假名、纯符号都归到这里）
    2. 假名数量 >= 汉字数量 → 按日文处理

    为什么用这个规则而不是「出现假名就算日文」：中文书名常带有日文作者前缀
    （例如 `[アイチルワークス (林チェリー)] 我心爱的温婉妻子…`），假名全部来自作者名，
    但汉字仍占多数。用比例判定可以放过这类正常书名，同时抓住整句日文。

    规则刻意偏向「保守」：日语短标题若汉字多于假名会返回 $true（漏判），
    代价是保持原值不变；反过来误判会覆盖用户已经写好的中文，代价大得多。
.PARAMETER Text
    待判定的文本。
.EXAMPLE
    Test-ChineseText -Text '我心爱的温婉妻子被夺走并怀上了别人的孩子'
    返回 $true。
.EXAMPLE
    Test-ChineseText -Text '僕の愛するおっとり妻が寝取られて孕まされた話'
    返回 $false（假名多于汉字）。
.INPUTS
    无
.OUTPUTS
    System.Boolean
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Test-ChineseText {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    [int]$HanCount = 0
    [int]$KanaCount = 0

    foreach ($Char in $Text.ToCharArray()) {
        [int]$Code = [int]$Char
        # 汉字：CJK 基本区、扩展 A、兼容区
        if (($Code -ge 0x4E00 -and $Code -le 0x9FFF) -or
            ($Code -ge 0x3400 -and $Code -le 0x4DBF) -or
            ($Code -ge 0xF900 -and $Code -le 0xFAFF)) {
            $HanCount++
        }
        # 假名：平假名 U+3040-309F、片假名 U+30A0-30FF
        elseif ($Code -ge 0x3040 -and $Code -le 0x30FF) {
            $KanaCount++
        }
    }

    if ($HanCount -eq 0) {
        return $false
    }

    return $KanaCount -lt $HanCount
}
