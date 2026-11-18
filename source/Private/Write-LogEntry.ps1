<#
.SYNOPSIS
    轻量日志函数，模仿 Python loguru 输出格式
.DESCRIPTION
    提供统一的日志输出接口，支持 INFO / SUCCESS / WARNING / ERROR 四个级别。
    输出格式为：时间戳 | 级别 | 调用者信息 - 消息，不同级别使用不同终端颜色。
    所有级别（含 Error）均为纯日志输出：只写终端，不抛出异常、不中断执行。
    需要"记录并中断"时，应在调用 Write-LogEntry 之后显式 throw 强类型异常
    （如 [System.IO.IOException]），日志与控制流分离。
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
function Write-LogEntry {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string] $Level,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Message
    )

    # 调用者信息：Get-PSCallStack 的 [0] 是本函数自身，[1] 才是直接调用者
    # （取 [2] 会落到「调用者的调用者」，把日志记到上一层调用的行号上）
    $CallStack = Get-PSCallStack
    $CallerFrame = $CallStack.Count -ge 2 ? $CallStack[1] : $null

    # 解析调用者信息：模块名:函数名:行号（脚本顶层没有函数段，退化为 模块名:行号）
    $CallerInfo = '<unknown>:0'
    if ($null -ne $CallerFrame) {
        # 模块名：模块内函数能取到真实模块名；普通脚本函数取不到时回退到脚本文件名
        [string]$Owner = $CallerFrame.InvocationInfo?.MyCommand?.ModuleName
        if (-not $Owner) {
            [string]$ScriptPath = $CallerFrame.ScriptName
            $Owner = $ScriptPath ? [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath) : '<script>'
        }

        # 函数名：脚本块与模块顶层不写函数段，避免出现 <ScriptBlock> 之类的噪声
        [string]$FuncName = $CallerFrame.FunctionName
        if ($FuncName -in @('<ScriptBlock>', '<module>')) {
            $FuncName = ''
        }

        # 行号（PS7 ?? 操作符：ScriptLineNumber 为 null 时回退到 0）
        $LineNumber = $CallerFrame.ScriptLineNumber ?? 0

        $CallerInfo = $FuncName ? "${Owner}:${FuncName}:${LineNumber}" : "${Owner}:${LineNumber}"
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
    if ($Level -eq 'Error') {
        Write-Host $Message -NoNewline -ForegroundColor White -BackgroundColor Red
    }
    else {
        Write-Host $Message -NoNewline -ForegroundColor $LevelColor
    }
    # 换行
    Write-Host ''

    # 所有级别（含 Error）到此结束：纯日志输出，不抛异常、不中断执行
    # 需要"记录并中断"时由调用方在本函数之后显式 throw 强类型异常
}
