<#
.SYNOPSIS
    判断一段文本是否是可读的简体中文
.DESCRIPTION
    纯函数：按字符类别做启发式判定，用于「中文字段里填的其实是原文」这种情况。

    判定规则：
    1. 没有汉字 → 不是中文（纯英文、纯假名、纯符号都归到这里）
    2. 出现任何假名 → 按日文处理；但**长文本**允许极少量假名：
       汉字不少于 100 且假名占比不超过 5% 时仍判为中文
       （典型场景：中文简介里引用了一个日文术语，如「ボテ腹」）

    为什么不是「假名少于汉字就算中文」：`あい漢語書` 这种「汉字多但夹着假名」的短文本
    显然不是可读的中文，早期版本会放过它。

    为什么长文本要开口子：真实项目的中文简介（2215 字）里引用了「ボテ腹」两个假名，
    如果一律判否，每次运行都会把用户写好的整篇简介重新翻译一遍——误判比漏判危险得多。

    带日文作者前缀的书名（`[アイチル…] 我心爱的妻子`）由调用方先剥掉前缀再判定，
    见 Test-NeedsTranslation——本函数只看传进来的文本本身。

    已知盲区：汉字写成的日文短标题（如 `淫らな妻` 去掉假名后）无法区分简繁与日文汉字，
    但这类文本通常出现在原文侧，不会遮挡补全；漏判只会保持原值，代价可控。
.PARAMETER Text
    待判定的文本。
.EXAMPLE
    Test-ChineseText -Text '我心爱的温婉妻子被夺走并怀上了别人的孩子'
    返回 $true。
.EXAMPLE
    Test-ChineseText -Text '僕の愛するおっとり妻が寝取られて孕まされた話'
    返回 $false（含假名）。
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
        # 假名：平假名 U+3040-309F、片假名 U+30A0-30FF、半角片假名 U+FF66-FF9D
        elseif (($Code -ge 0x3040 -and $Code -le 0x30FF) -or
            ($Code -ge 0xFF66 -and $Code -le 0xFF9D)) {
            $KanaCount++
        }
    }

    if ($HanCount -eq 0) {
        return $false
    }

    if ($KanaCount -eq 0) {
        return $true
    }

    # 长文本里允许极少量假名（多半是引用的日文术语）；短文本一律判否
    return $HanCount -ge 100 -and ($KanaCount * 20) -le $HanCount
}
