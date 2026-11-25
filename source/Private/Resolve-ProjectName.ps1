<#
.SYNOPSIS
    由作者名与原作品名拼出项目目录名
.DESCRIPTION
    唯一的命名入口：`[作者] 原作品名`。项目目录名与 README.toml 里的标题都来自这里，
    避免两处各拼一次而出现分歧。

    作者名或原作品名为空时交互补齐（配置里没填时仍能得到可用的目录名）；
    两个值都会 Trim 后再拼接，纯空白等同于未提供。
.PARAMETER Author
    作者名。
.PARAMETER OriginalTitle
    原作品名（原文）。
.EXAMPLE
    Resolve-ProjectName -Author '某作者' -OriginalTitle '某作品'
    返回 '[某作者] 某作品'。
.INPUTS
    无
.OUTPUTS
    System.String
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Resolve-ProjectName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [AllowEmptyString()]
        [string]$Author = '',

        [AllowEmptyString()]
        [string]$OriginalTitle = ''
    )

    [string]$ResolvedAuthor = ([string]$Author).Trim()
    if (-not $ResolvedAuthor) {
        $ResolvedAuthor = Read-TrimmedInput -Prompt '作者名'
    }

    [string]$ResolvedTitle = ([string]$OriginalTitle).Trim()
    if (-not $ResolvedTitle) {
        $ResolvedTitle = Read-TrimmedInput -Prompt '原作品名（原文）'
    }

    return "[$ResolvedAuthor] $ResolvedTitle"
}
