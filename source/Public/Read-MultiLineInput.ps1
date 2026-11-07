<#
.SYNOPSIS
    交互式读取用户的多行文本输入
.DESCRIPTION
    逐键读取控制台输入，支持 Enter 换行、Ctrl+D 结束输入、退格与 Delete 清空当前行。
    每按一次 Enter 将当前行内容存入结果集合，Ctrl+D 结束后返回所有行。
    按键判定与循环分别由私有函数 Get-MultiLineEditAction / Invoke-MultiLineReader 承担。
.PARAMETER Prompt
    (string, Optional) 显示在输入前的提示文本。
.EXAMPLE
    $lines = Read-MultiLineInput -Prompt '请输入项目简介（Ctrl+D 结束输入）'
    交互式读取多行输入，返回各行字符串。
.INPUTS
    无
.OUTPUTS
    string（每行输入文本作为一个字符串对象，逐个返回）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Read-MultiLineInput {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string]$Prompt
    )

    # 真实的按键读取与终端渲染由 Invoke-MultiLineReader 的默认适配器提供
    return Invoke-MultiLineReader -Prompt $Prompt
}
