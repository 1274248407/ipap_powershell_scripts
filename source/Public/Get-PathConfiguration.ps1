<#
.SYNOPSIS
    获取路径配置
.DESCRIPTION
    从配置实例获取路径配置对象。
.EXAMPLE
    Get-PathConfiguration
    获取路径配置对象。
.INPUTS
    无
.OUTPUTS
    PathConfiguration
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-PathConfiguration
{
    [CmdletBinding()]
    [OutputType('PathConfiguration')]
    param()

    return (Get-Configuration).Paths
}

