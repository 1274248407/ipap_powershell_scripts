<#
.SYNOPSIS
    判断中文字段是否需要重新翻译
.DESCRIPTION
    纯函数：四个条件任一成立就返回 $true。
    1. 空或纯空白
    2. 与 config.toml.example 里的占位文本相同（例如 `中文译名`）
    3. 与原文完全相同（把日文书名直接贴进了中文字段）
    4. 不是中文（见 Test-ChineseText：纯英文、或假名多于汉字的整句日文）

    条件 2 的占位文本由调用方从示例文件实时读取，不在代码里硬编码文案。
.PARAMETER Value
    当前字段值（中文译名或中文简介）。
.PARAMETER Placeholder
    示例文件里该字段的占位文本；为空表示不做占位符比对。
.PARAMETER Original
    对应的原文（原作品名或原文简介）；为空表示不做「与原文相同」比对。
.EXAMPLE
    Test-NeedsTranslation -Value '中文译名' -Placeholder '中文译名' -Original '僕の妻'
    返回 $true。
.EXAMPLE
    Test-NeedsTranslation -Value '我心爱的妻子' -Placeholder '中文译名' -Original '僕の妻'
    返回 $false。
.INPUTS
    无
.OUTPUTS
    System.Boolean
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Test-NeedsTranslation {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [AllowEmptyString()]
        [string]$Placeholder = '',

        [AllowEmptyString()]
        [string]$Original = ''
    )

    [string]$Trimmed = $Value.Trim()
    if (-not $Trimmed) {
        return $true
    }

    if ($Placeholder -and $Trimmed -eq $Placeholder.Trim()) {
        return $true
    }

    if ($Original -and $Trimmed -eq $Original.Trim()) {
        return $true
    }

    # 方括号里是作者名（专有名词），判定语种时只看正文，避免作者前缀把中文书名压成「日文」
    [string]$BodyForLanguage = (Split-AuthorPrefix -Title $Trimmed).Body
    return -not (Test-ChineseText -Text $BodyForLanguage)
}
