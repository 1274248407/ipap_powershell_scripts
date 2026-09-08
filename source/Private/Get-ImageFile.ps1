﻿<#
.SYNOPSIS
扫描目录中的图片文件
.DESCRIPTION
遍历指定目录，筛选出支持的图片格式文件并返回 FileInfo 对象数组。
仅负责扫描与过滤，排序由调用方按需处理。
SupportedFormats 为空时委托 Test-SupportedImageFormat 从模块配置读取默认格式列表。
.PARAMETER Path
(string,Mandatory) 要扫描的目录路径。
.PARAMETER SupportedFormats
(string[],Optional) 支持的图片扩展名列表（如 @('.jpg', '.png')）。
为空则使用配置中的默认格式列表。
.EXAMPLE
Get-ImageFile -Path 'D:\Images'
返回 D:\Images 下所有支持格式的图片文件。
.EXAMPLE
Get-ImageFile -Path 'D:\Images' -SupportedFormats @('.jpg', '.png')
返回指定格式的图片文件。
.INPUTS
无
.OUTPUTS
System.IO.FileInfo（输出零个或多个图片文件对象）
.NOTES
Author: lucas_gold
Website: https://github.com/1274248407
#>

function Get-ImageFile
{
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string[]]$SupportedFormats = $null
    )

    # 获取图片文件：按支持格式筛选，不排序（排序由调用方决定）
    Get-ChildItem -LiteralPath $Path -File | Where-Object {
        Test-SupportedImageFormat -File $PSItem -SupportedFormats $SupportedFormats
    }
}
