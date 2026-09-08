<#
.SYNOPSIS
    提示用户输入项目相关的多行信息并格式化
.DESCRIPTION
    提示用户输入项目名称、作品中文译名和原文项目简介以及中文项目简介，
    然后将这些信息按照特定模板格式化为一个字符串，并返回格式化后的
    字符串和项目名称。
.EXAMPLE
    Get-ProjectBriefInfo
    获取项目简介信息并返回格式化后的字符串和项目名称。
.INPUTS
    无
.OUTPUTS
    object[] (包含格式化字符串和项目名称)
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>

function Read-MultiLineInput
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
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

