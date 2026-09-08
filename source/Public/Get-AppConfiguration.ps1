<#
.SYNOPSIS
    获取应用配置
.DESCRIPTION
    从配置实例获取应用配置对象。
.EXAMPLE
    Get-AppConfiguration
    获取应用配置对象。
.INPUTS
    无
.OUTPUTS
    ApplicationConfiguration
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-AppConfiguration
{
    [CmdletBinding()]
    [OutputType('ApplicationConfiguration')]
    param()

    return (Get-Configuration).App
}

