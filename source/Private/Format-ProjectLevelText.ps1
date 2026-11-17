<#
.SYNOPSIS
    把项目统一等级格式化为可读文本
.DESCRIPTION
    纯函数：把 0/1/2 的项目等级转成写给日志与 README 的中文描述。
    统一在这里维护措辞，避免日志与 README 各写一份而逐渐不一致。
.PARAMETER Level
    项目统一等级（0/1/2）。
.PARAMETER RealCuganScale
    Real-CUGAN 的放大倍数（-s），仅 Level 2 时出现在描述里，默认 2。
.EXAMPLE
    Format-ProjectLevelText -Level 1
    返回 'Level 1（FFmpeg 1.2 倍放大 + 锐化）'。
.EXAMPLE
    Format-ProjectLevelText -Level 2 -RealCuganScale 4
    返回 'Level 2（Real-CUGAN 4 倍超分）'。
.INPUTS
    无
.OUTPUTS
    System.String
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Format-ProjectLevelText {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2)]
        [int]$Level,

        [ValidateRange(1, 4)]
        [int]$RealCuganScale = 2
    )

    switch ($Level) {
        0 { return 'Level 0（已高清，不放大）' }
        1 { return 'Level 1（FFmpeg 1.2 倍放大 + 锐化）' }
        default { return "Level 2（Real-CUGAN $RealCuganScale 倍超分）" }
    }
}
