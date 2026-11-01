<#
.SYNOPSIS
    将单个按键转换为多行输入编辑动作
.DESCRIPTION
    纯函数：根据当前按键、当前行内容与提示语，返回下一步编辑动作。
    不读取控制台、不写终端，便于单元测试完整覆盖 Enter/Backspace/Delete/Ctrl+D/可打印字符。
.PARAMETER Key
    当前按下的 ConsoleKeyInfo。
.PARAMETER CurrentLine
    当前正在编辑的行内容。
.PARAMETER Prompt
    输入提示语，用于计算 Delete 清行时需要覆盖的字符数。
.EXAMPLE
    Get-MultiLineEditAction -Key $key -CurrentLine 'abc' -Prompt '简介'
.INPUTS
    无
.OUTPUTS
    PSCustomObject（Type / CurrentLine / LinesToAdd / Text / ClearLength）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-MultiLineEditAction {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ConsoleKeyInfo]$Key,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$CurrentLine,

        [AllowEmptyString()]
        [string]$Prompt = ''
    )

    # Ctrl+D / Ctrl+d：结束输入；当前行非空时先追加
    if (($Key.Modifiers -band [ConsoleModifiers]::Control) -and
        ($Key.KeyChar -eq [char]4 -or $Key.KeyChar -eq [char]'d')) {
        [string[]]$linesToAdd = $CurrentLine.Length -gt 0 ? @($CurrentLine) : @()
        return [PSCustomObject]@{
            Type        = 'Submit'
            CurrentLine = ''
            LinesToAdd  = $linesToAdd
            Text        = ''
            ClearLength = 0
        }
    }

    switch ($Key.Key) {
        # Enter：把当前行（即使为空行）追加到结果集，并清空当前行
        { $PSItem -eq [ConsoleKey]::Enter } {
            return [PSCustomObject]@{
                Type        = 'NewLine'
                CurrentLine = ''
                LinesToAdd  = @($CurrentLine)
                Text        = ''
                ClearLength = 0
            }
        }

        # Backspace：删除当前行最后一个字符
        { $PSItem -eq [ConsoleKey]::Backspace } {
            if ($CurrentLine.Length -gt 0) {
                return [PSCustomObject]@{
                    Type        = 'Backspace'
                    CurrentLine = $CurrentLine.Substring(0, $CurrentLine.Length - 1)
                    LinesToAdd  = @()
                    Text        = ''
                    ClearLength = 0
                }
            }
        }

        # Delete：清空当前整行（当前实现没有光标位置，语义为 ClearLine）
        { $PSItem -eq [ConsoleKey]::Delete } {
            if ($CurrentLine.Length -gt 0) {
                return [PSCustomObject]@{
                    Type        = 'ClearLine'
                    CurrentLine = ''
                    LinesToAdd  = @()
                    Text        = ''
                    ClearLength = $CurrentLine.Length + $Prompt.Length
                }
            }
        }

        # 可打印字符（含空格）：追加到当前行
        default {
            if ($Key.KeyChar -and $Key.KeyChar -ge ' ') {
                [string]$text = [string]$Key.KeyChar
                return [PSCustomObject]@{
                    Type        = 'Append'
                    CurrentLine = $CurrentLine + $text
                    LinesToAdd  = @()
                    Text        = $text
                    ClearLength = 0
                }
            }
        }
    }

    # 其余按键（方向键、控制字符等）忽略
    return [PSCustomObject]@{
        Type        = 'Ignore'
        CurrentLine = $CurrentLine
        LinesToAdd  = @()
        Text        = ''
        ClearLength = 0
    }
}
