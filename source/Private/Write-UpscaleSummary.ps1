<#
.SYNOPSIS
    汇总高清化结果并输出逐图日志
.DESCRIPTION
    遍历 Invoke-UpscaleProcess 的结果数组，成功记 Info、失败记 Warning，
    并返回成功/失败计数。单张失败不中断批次。
.PARAMETER Results
    Invoke-UpscaleProcess 返回的结果对象数组（Success / Image / Error）。
.EXAMPLE
    Write-UpscaleSummary -Results $results
.INPUTS
    无
.OUTPUTS
    PSCustomObject（SuccessCount / FailedCount）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Write-UpscaleSummary {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    [int]$successCount = 0
    [int]$failedCount = 0

    foreach ($result in $Results) {
        if ($result.Success) {
            Write-LogEntry -Level Info -Message "图片处理成功: $($result.Image)"
            $successCount++
        }
        else {
            # 单张图片失败不中断批次，降级为警告日志并计入失败数
            Write-LogEntry -Level Warning -Message "图片处理失败: $($result.Image)"
            $failedCount++
        }
    }

    return [PSCustomObject]@{
        SuccessCount = $successCount
        FailedCount  = $failedCount
    }
}
