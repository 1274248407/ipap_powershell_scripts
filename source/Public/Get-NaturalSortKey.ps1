<#
.SYNOPSIS
    生成自然排序键
.DESCRIPTION
    将文件名转换为自然排序键，实现数字在字符串中的自然排序。
    例如：file1.txt, file10.txt, file2.txt 会按数字大小排序。
.PARAMETER InputString
    (string, Mandatory) 输入字符串。
    （适用于所有参数集）
.EXAMPLE
    Get-NaturalSortKey -InputString "image10.png"
    生成自然排序键。
.INPUTS
    string
.OUTPUTS
    string
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-NaturalSortKey
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputString
    )

    # 使用正则分割字符串，捕获数字部分
    $parts = [regex]::Split($InputString, '(\d+)')

    # 过滤空字符串，数字部分零填充（10位）
    $result = $parts | Where-Object { -not [string]::IsNullOrEmpty($PSItem) } | ForEach-Object {
        if ($PSItem -match '^\d+$')
        {
            $PSItem.PadLeft(10, '0')
        }
        else
        {
            $PSItem
        }
    }

    return $result -join ''
}

