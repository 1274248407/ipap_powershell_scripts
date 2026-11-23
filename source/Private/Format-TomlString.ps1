<#
.SYNOPSIS
    把字符串格式化为 TOML 单行基本字符串
.DESCRIPTION
    纯函数：输出带双引号的 TOML 基本字符串（basic string），并转义反斜杠、双引号与控制字符。
    用于作者名、作品名这类单行字段；多行文本请用 Format-TomlMultilineString。
.PARAMETER Value
    原始字符串，可为空。
.EXAMPLE
    Format-TomlString -Value 'C:\Images'
    返回 '"C:\\Images"'。
.INPUTS
    无
.OUTPUTS
    System.String
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Format-TomlString {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    [System.Text.StringBuilder]$Builder = [System.Text.StringBuilder]::new('"')

    foreach ($Char in $Value.ToCharArray()) {
        if ($Char -eq '\') {
            [void]$Builder.Append('\\')
        }
        elseif ($Char -eq '"') {
            [void]$Builder.Append('\"')
        }
        elseif ($Char -eq "`b") {
            [void]$Builder.Append('\b')
        }
        elseif ($Char -eq "`t") {
            [void]$Builder.Append('\t')
        }
        elseif ($Char -eq "`n") {
            [void]$Builder.Append('\n')
        }
        elseif ($Char -eq "`f") {
            [void]$Builder.Append('\f')
        }
        elseif ($Char -eq "`r") {
            [void]$Builder.Append('\r')
        }
        elseif ([int]$Char -lt 0x20 -or [int]$Char -eq 0x7F) {
            # 其余控制字符没有专用转义，统一写成 \uXXXX
            [void]$Builder.Append(('\u{0:X4}' -f [int]$Char))
        }
        else {
            [void]$Builder.Append($Char)
        }
    }

    [void]$Builder.Append('"')
    return $Builder.ToString()
}
