<#
.SYNOPSIS
    记录 Warning 级别日志
.DESCRIPTION
    Write-LogEntry 的语义化包装函数，固定使用 Warning 级别。
    保持与原 PoShLog Write-WarningLog 相同的调用方式，降低迁移成本。
    @see 核心 logger 见 source/Private/Write-LogEntry.ps1
.PARAMETER Message
    (string) 日志消息内容
.EXAMPLE
    Write-WarningLog "未找到配置文件，使用默认配置"
.INPUTS
    [string]
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Write-WarningLog
{
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyString()]
        [string] $Message
    )

    # 委托给核心日志函数
    Write-LogEntry -Level 'Warning' -Message $Message
}
