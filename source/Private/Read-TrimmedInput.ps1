<#
.SYNOPSIS
    读取一行输入并去除首尾空白
.DESCRIPTION
    包装 Read-Host，统一处理非交互环境（stdin 已 EOF）下的返回值：
    Read-Host 在 EOF 时返回的是 AutomationNull——它与 $null 相等，但不支持方法调用，
    直接对它调用 .Trim() 会抛「不能对值为 Null 的表达式调用方法」。
    本函数先判空再 Trim，非交互环境一律返回空字符串，由调用方按「未提供」处理。
.PARAMETER Prompt
    提示文本。
.EXAMPLE
    $SourceDir = Read-TrimmedInput -Prompt '请输入源图片目录'
.INPUTS
    无
.OUTPUTS
    System.String（非交互环境返回空字符串，不返回 $null）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Read-TrimmedInput {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    # EOF 时 Read-Host 返回 AutomationNull：与 $null 相等但不能调用方法，必须先判空
    $RawInput = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($RawInput)) {
        return ''
    }

    return ([string]$RawInput).Trim()
}
