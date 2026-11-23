<#
.SYNOPSIS
    把字符串格式化为 TOML 多行字符串
.DESCRIPTION
    纯函数：优先用多行字面量（''') 包裹，让日文 / 中文原文与反斜杠保持原样可读；
    内容本身含三连单引号或以单引号结尾时无法用字面量，退回多行基本字符串（"""）并转义反斜杠与双引号。
    两种情况都会在起始分隔符后补一个换行——TOML 规定起始分隔符后紧跟的换行会被裁掉，
    这样正文字符串可以原样写回，不多也不少一个换行。
.PARAMETER Value
    原始文本，可为空；内部换行原样保留。
.EXAMPLE
    Format-TomlMultilineString -Value "第一行`n第二行"
    返回含三引号包裹的多行字符串。
.INPUTS
    无
.OUTPUTS
    System.String
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Format-TomlMultilineString {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    # 字面量（'''）不能包含三连单引号；结尾的单个引号会与闭合分隔符连成四个引号，同样不可用
    [bool]$CanUseLiteral = -not $Value.Contains("'''") -and -not $Value.EndsWith("'")
    if ($CanUseLiteral) {
        return "'''`n${Value}'''"
    }

    [string]$Escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"""' + "`n" + $Escaped + '"""'
}
