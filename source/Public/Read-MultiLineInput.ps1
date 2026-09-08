<#
.SYNOPSIS
    交互式读取用户的多行文本输入
.DESCRIPTION
    逐键读取控制台输入，支持 Enter 换行、Ctrl+D 结束输入、退格与 Delete 行内编辑。
    每按一次 Enter 将当前行内容存入结果集合，Ctrl+D 结束后返回所有行。
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

function Read-MultiLineInput
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string]$Prompt
    )

    [array]$lines = @()
    # 创建一个"字符串构建器"。在循环中频繁修改字符串时，使用 StringBuilder 比直接用 += 拼接字符串性能更高。
    [System.Text.StringBuilder]$currentLine = [System.Text.StringBuilder]::new()

    if ($Prompt)
    {
        Write-Host $Prompt
    }

    while ($true)
    {
        $key = [Console]::ReadKey($true)

        # 检查是否按下了 Ctrl 修饰键
        if ($key.Modifiers -band [ConsoleModifiers]::Control)
        {
            # 且同时按下了 D（[char]4 是终端中 Ctrl+D 的控制字符），则退出循环
            if ($key.KeyChar -eq [char]4 -or $key.KeyChar -eq [char]'d')
            {
                if ($currentLine.Length -gt 0)
                {
                    $lines += $currentLine.ToString()
                }
                break
            }
        }

        switch ($key.Key)
        {
            # 将当前行存入 $lines 数组，清空 $currentLine 准备接收下一行，并换行显示。
            { $PSItem -eq [ConsoleKey]::Enter }
            {
                $lines += $currentLine.ToString()
                $currentLine.Clear()
                Write-Host
            }
            # 如果当前行有字符，将长度减 1（删除最后一个字符）。 `b `b 是在控制台把光标往回退一格并覆盖原字符，实现视觉上的删除。
            { $PSItem -eq [ConsoleKey]::Backspace }
            {
                if ($currentLine.Length -gt 0)
                {
                    $currentLine.Length = $currentLine.Length - 1
                    Write-Host "`b `b" -NoNewline
                }
            }
            # 直接清空当前行所有内容。通过打印 80 个空格覆盖原内容，再重新打印提示语和清空后的当前行。
            { $PSItem -eq [ConsoleKey]::Delete }
            {
                if ($currentLine.Length -gt 0)
                {
                    # 保存当前长度用于清除屏幕
                    $clearLength = $currentLine.Length + $Prompt.Length
                    $currentLine.Clear()
                    # 动态生成所需数量的空格
                    $spaces = ' ' * $clearLength
                    Write-Host "`r$spaces`r" -NoNewline
                    Write-Host $Prompt -NoNewline
                    Write-Host $currentLine.ToString() -NoNewline
                }
            }
            # 如果是可打印字符（ASCII 码大于空格），追加到 $currentLine，
            # 并用 Write-Host 显示在屏幕上。[void] 用于忽略 Append 方法的返回值
            default
            {
                if ($key.KeyChar -and $key.KeyChar -ge ' ')
                {
                    [void]$currentLine.Append($key.KeyChar)
                    Write-Host $key.KeyChar -NoNewline
                }
            }
        }
    }

    return $lines
}
