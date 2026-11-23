<#
.SYNOPSIS
    把数字格式化为 TOML 可读的小数文本
.DESCRIPTION
    纯函数：按指定小数位四舍五入，再用 InvariantCulture 输出，
    避免小数点随系统区域设置变成逗号（TOML 只认点）。
    末尾多余的 0 会去掉（1920.0 → 1920，5.20 → 5.2）。
.PARAMETER Value
    待格式化的数值。
.PARAMETER Decimals
    保留的最大小数位，默认 2。
.EXAMPLE
    Format-TomlNumber -Value 5.21
    返回 '5.21'。
.INPUTS
    无
.OUTPUTS
    System.String
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Format-TomlNumber {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [double]$Value,

        [ValidateRange(0, 15)]
        [int]$Decimals = 2
    )

    [double]$Rounded = [math]::Round($Value, $Decimals)
    [string]$Format = '0' + ($Decimals -gt 0 ? '.' + ('#' * $Decimals) : '')
    return $Rounded.ToString($Format, [System.Globalization.CultureInfo]::InvariantCulture)
}
