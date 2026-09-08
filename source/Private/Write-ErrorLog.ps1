<#
.SYNOPSIS
    记录 Error 级别日志并抛出终止错误
.DESCRIPTION
    Write-LogEntry 的语义化包装函数，固定使用 Error 级别。
    与原 PoShLog Write-ErrorLog 不同：本函数记录日志后会抛出终止错误（throw），
    调用点之后的代码不会执行。原有 `Write-ErrorLog ...; return` 模式中的
    return 已不可达，应在迁移时清理。
    @see 核心 logger 见 source/Private/Write-LogEntry.ps1
.PARAMETER Message
    (string) 日志消息内容
.EXAMPLE
    Write-ErrorLog "未找到 FFmpeg"
    # 输出红色错误日志后抛出终止错误
.INPUTS
    [string]
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Write-ErrorLog
{
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string] $Message
    )

    # 委托给核心日志函数（Error 级别会 throw 终止错误）
    Write-LogEntry -Level 'Error' -Message $Message
}
