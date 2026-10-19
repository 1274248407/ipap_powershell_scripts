<#
.SYNOPSIS
    读取指定范围内的整数输入
.DESCRIPTION
    循环提示用户输入，直到收到 Min 与 Max 之间（含端点）的整数。
    非数字输入与越界输入分别给出提示后重新提问；
    若标准输入已结束（EOF），则不再重问，直接返回空，由调用方决定后续行为。
    该函数封装「EOF 守卫 + 类型解析 + 范围校验 + 重问」四件事，
    避免各调用点各写一份而漏掉其中一环。
.PARAMETER Prompt
    (string, Mandatory) 提示文本。
.PARAMETER Min
    (int, Mandatory) 允许的最小值（含）。
.PARAMETER Max
    (int, Mandatory) 允许的最大值（含）。
.EXAMPLE
    $Choice = Read-NumberInRange -Prompt '请输入选项 (1-3)' -Min 1 -Max 3
    读取 1 到 3 之间的整数。
.EXAMPLE
    $StartIndex = Read-NumberInRange -Prompt '请输入起始编号 (1-50，输入 0 跳过)' -Min 0 -Max 50
    读取 0 到 50 之间的整数（0 由调用方解释为跳过）。
.INPUTS
    无
.OUTPUTS
    System.Int32（读取成功时输出一个整数；EOF 时无输出）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Read-NumberInRange {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $true)]
        [int]$Min,
        [Parameter(Mandatory = $true)]
        [int]$Max
    )

    while ($true) {
        [string]$RawInput = Read-Host $Prompt
        # 非交互环境（stdin 已 EOF）下 Read-Host 恒返回 $null：不再重问，交由调用方按跳过处理
        if ([string]::IsNullOrWhiteSpace($RawInput)) {
            return
        }

        try {
            [int]$Parsed = $RawInput
        }
        catch {
            Write-LogEntry -Level Warning -Message '请输入有效的数字'
            continue
        }

        if ($Parsed -lt $Min -or $Parsed -gt $Max) {
            Write-LogEntry -Level Warning -Message "请输入 $Min 到 $Max 之间的数字"
            continue
        }

        return $Parsed
    }
}
