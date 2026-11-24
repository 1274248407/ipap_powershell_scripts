<#
.SYNOPSIS
    从书名里拆出 [作者] 前缀
.DESCRIPTION
    纯函数：把 `[作者] 正文` 拆成前缀与正文两段，供翻译时「只送正文、再拼回前缀」使用。
    方括号里的作者名是专有名词，任何模型都可能顺手改写或翻译，所以不让它进入请求。
    支持半角 `[...]` 与全角 `【...】`；不含前缀时 Prefix 为空、Body 为原文。
.PARAMETER Title
    完整书名，例如 `[アイチルワークス (林チェリー)] 僕の愛するおっとり妻…`。
.EXAMPLE
    Split-AuthorPrefix -Title '[作者] 标题'
    返回 @{ Prefix = '[作者]'; Body = '标题' }。
.INPUTS
    无
.OUTPUTS
    PSCustomObject（含 Prefix / Body 两个字符串属性）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Split-AuthorPrefix {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Title
    )

    if ($Title -match '^\s*(?<Prefix>\[[^\]]*\]|【[^】]*】)(?<Body>.*)$') {
        return [PSCustomObject]@{
            Prefix = $Matches.Prefix.Trim()
            Body   = $Matches.Body.Trim()
        }
    }

    return [PSCustomObject]@{
        Prefix = ''
        Body   = $Title.Trim()
    }
}
