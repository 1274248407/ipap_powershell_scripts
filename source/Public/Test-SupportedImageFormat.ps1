<#
.SYNOPSIS
    检查文件是否为支持的图片格式
.DESCRIPTION
    判断给定文件对象的扩展名是否在支持的图片格式列表中。
    封装了重复的格式检查逻辑，提高代码复用性。
    支持管道输入，可以批量检查多个文件对象。
.PARAMETER File
    (object, Mandatory) 文件对象，需要包含 Extension 属性。
    支持 System.IO.FileInfo 和任何具有 Extension 属性的对象。
.PARAMETER SupportedFormats
    (string[], Optional) 支持的图片格式列表，若未指定则从配置读取。
.EXAMPLE
    Get-ChildItem -Path "C:\Images" -File | Test-SupportedImageFormat
    通过管道批量检查目录中所有文件是否为支持的图片格式。
.EXAMPLE
    Get-ChildItem -Path "C:\Images" -File | Where-Object { Test-SupportedImageFormat -File $PSItem }
    筛选出目录中所有支持的图片文件（非管道方式）。
.EXAMPLE
    Test-SupportedImageFormat -File $file -SupportedFormats @('.jpg', '.png')
    使用自定义格式列表检查文件。
.INPUTS
    object (通过管道输入文件对象)
.OUTPUTS
    bool (每个输入对象返回一个布尔值)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Test-SupportedImageFormat
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$File,
        [Parameter(Mandatory = $false)]
        [string[]]$SupportedFormats = $null
    )

    begin
    {
        # 只在调用者未提供 SupportedFormats 时从配置读取
        if (-not $SupportedFormats)
        {
            $SupportedFormats = Get-SupportedImageFormat
        }
    }

    process
    {
        # 检查输入对象是否包含 Extension 属性
        if (-not $File.PSObject.Properties['Extension'])
        {
            Write-LogEntry -Level Warning -Message '输入对象缺少 Extension 属性'
            return $false
        }

        # 检查 Extension 值是否为 null 或空
        if (-not $File.Extension)
        {
            return $false
        }

        return $SupportedFormats -contains $File.Extension.ToLower()
    }
}

