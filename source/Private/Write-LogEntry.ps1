﻿<#
.SYNOPSIS
    轻量日志函数，模仿 Python loguru 输出格式
.DESCRIPTION
    提供统一的日志输出接口，支持 INFO / SUCCESS / WARNING / ERROR 四个级别。
    输出格式为：时间戳 | 级别 | 调用者信息 - 消息，不同级别使用不同终端颜色。
    ERROR 级别输出日志后会抛出终止错误，保持与 $ErrorActionPreference = 'Stop' 的兼容性。
    本函数已通过 Export-ModuleMember 导出，供模块外部（如 Main.ps1 入口脚本）记录启动事件。
    @see 移植自 FinalizeAndArchiveProject 项目 source/Private/Write-LogEntry.ps1
.PARAMETER Level
    (ValidateSet) 日志级别，可选值为 Info、Success、Warning、Error
.PARAMETER Message
    (string) 日志消息内容
.EXAMPLE
    Write-LogEntry -Level Info -Message "备份创建成功"
.EXAMPLE
    Write-LogEntry -Level Error -Message "配置文件不存在"
.INPUTS
    [string]
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Write-LogEntry
{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string] $Level,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    # 获取调用者信息：跳过 Write-LogEntry 自身（索引1），取实际调用者（索引2）
    # PS7 if 表达式：直接返回匹配分支的值（深栈取 [2]，浅栈取 [1]，单帧返回 $null）
    $CallStack = Get-PSCallStack
    $CallerFrame = if ($CallStack.Count -ge 3) { $CallStack[2] }
    elseif ($CallStack.Count -ge 2) { $CallStack[1] }
    else { $null }

    # 解析调用者信息：模块名:函数名:行号
    $CallerInfo = '<unknown>:<unknown>:0'
    if ($null -ne $CallerFrame)
    {
        # 从脚本路径提取模块名（父目录名）
        $ScriptPath = $CallerFrame.ScriptName
        $ModuleName = '<script>'
        if ($ScriptPath)
        {
            $ParentDir = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($ScriptPath))
            if ($ParentDir)
            {
                $ModuleName = $ParentDir
            }
        }

        # 获取函数名（匿名脚本块显示为 <ScriptBlock>）
        $FuncName = $CallerFrame.FunctionName
        if ($FuncName -eq '<ScriptBlock>')
        {
            $FuncName = '<module>'
        }

        # 获取行号（PS7 ?? 操作符：ScriptLineNumber 为 null 时回退到 0）
        $LineNumber = $CallerFrame.ScriptLineNumber ?? 0

        $CallerInfo = "${ModuleName}:${FuncName}:${LineNumber}"
    }

    # 格式化时间戳（精确到毫秒）
    $Timestamp = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')

    # 级别名称右对齐到7字符（匹配 loguru 的列宽）
    $LevelText = $Level.ToUpper().PadRight(7)

    # 根据级别选择颜色
    $LevelColorMap = @{
        'Info'    = 'White'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }
    $LevelColor = $LevelColorMap[$Level]

    # loguru 风格分段配色：时间戳暗色 | 级别亮色 | 调用者青色 | 消息随级别色
    # 输出时间戳（暗灰色）
    Write-Host "${Timestamp} " -NoNewline -ForegroundColor DarkGray
    # 输出分隔符 + 级别（级别对应颜色）
    Write-Host "| ${LevelText} | " -NoNewline -ForegroundColor $LevelColor
    # 输出调用者信息（青色）
    Write-Host "${CallerInfo} - " -NoNewline -ForegroundColor Cyan
    # 输出消息（级别对应颜色，ERROR 级别加红色背景）
    if ($Level -eq 'Error')
    {
        Write-Host $Message -NoNewline -ForegroundColor White -BackgroundColor Red
    }
    else
    {
        Write-Host $Message -NoNewline -ForegroundColor $LevelColor
    }
    # 换行
    Write-Host ''

    # ERROR 级别抛出终止错误，保持错误传播链
    if ($Level -eq 'Error')
    {
        throw $Message
    }
}
