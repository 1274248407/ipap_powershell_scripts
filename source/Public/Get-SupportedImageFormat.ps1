<#
.SYNOPSIS
    获取支持的图片格式
.DESCRIPTION
    从配置实例读取支持的图片格式列表。
.EXAMPLE
    Get-SupportedImageFormat
    获取支持的图片格式数组。
.INPUTS
    无
.OUTPUTS
    string[]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-SupportedImageFormat
{
    [CmdletBinding()]
    param()

    return (Get-Configuration).App.SupportedImageFormats
}

