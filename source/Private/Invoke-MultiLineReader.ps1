<#
.SYNOPSIS
    逐键读取多行文本输入
.DESCRIPTION
    从可注入的 ReadKey 读取按键，按 Get-MultiLineEditAction 返回的动作更新行缓冲，
    并通过可注入的 WriteOutput 渲染到终端。Ctrl+D 结束输入并返回所有行。
    默认 ReadKey / WriteOutput 直接操作真实控制台；单元测试可注入假实现。
.PARAMETER ReadKey
    读取一个 ConsoleKeyInfo 的脚本块，默认 [Console]::ReadKey($true)。
.PARAMETER WriteOutput
    输出文本的脚本块，参数为 Text 与 NoNewline，默认使用 Write-Host。
.PARAMETER Prompt
    输入前的提示语。
.EXAMPLE
    Invoke-MultiLineReader -Prompt '请输入简介（Ctrl+D 结束输入）'
.INPUTS
    无
.OUTPUTS
    string（每行输入文本作为一个字符串对象，逐个返回）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Invoke-MultiLineReader {
    # 豁免 PSAvoidUsingWriteHost：默认渲染器需要逐字符实时显示
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [scriptblock]$ReadKey = { [Console]::ReadKey($true) },

        [scriptblock]$WriteOutput = {
            param([string]$Text, [switch]$NoNewline)
            if ($NoNewline) { Write-Host $Text -NoNewline }
            else { Write-Host $Text }
        },

        [AllowEmptyString()]
        [string]$Prompt = ''
    )

    [string[]]$lines = @()
    [string]$currentLine = ''

    if ($Prompt) {
        & $WriteOutput -Text $Prompt
    }

    while ($true) {
        [ConsoleKeyInfo]$key = & $ReadKey
        [PSCustomObject]$action = Get-MultiLineEditAction -Key $key -CurrentLine $currentLine -Prompt $Prompt

        if ($action.LinesToAdd.Count -gt 0) {
            $lines += $action.LinesToAdd
        }
        $currentLine = $action.CurrentLine

        switch ($action.Type) {
            'Append' {
                & $WriteOutput -Text $action.Text -NoNewline
            }
            'Backspace' {
                & $WriteOutput -Text "`b `b" -NoNewline
            }
            'ClearLine' {
                [string]$spaces = ' ' * $action.ClearLength
                & $WriteOutput -Text "`r$spaces`r$Prompt$($action.CurrentLine)" -NoNewline
            }
            'NewLine' {
                & $WriteOutput -Text ''
            }
            'Submit' {
                return $lines
            }
        }
    }
}
