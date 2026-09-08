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

