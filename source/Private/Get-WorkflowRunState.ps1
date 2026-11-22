<#
.SYNOPSIS
    读取项目的运行状态标记
.DESCRIPTION
    工作流开始处理前会在项目根目录写 `.ipap-run.json`，校验通过后删除。
    下次运行如果读到这个文件，说明上次没有跑完，可以据此自动续跑。
    文件不存在、内容为空或无法解析时一律返回 $null（按「没有状态」处理），
    不让一个坏文件卡住整个流程。
.PARAMETER ProjectDir
    项目根目录。
.EXAMPLE
    $state = Get-WorkflowRunState -ProjectDir 'C:\Projects\2026-11-22_某项目'
.INPUTS
    无
.OUTPUTS
    PSCustomObject（含 projectLevel / realCuganScale / modelSelect / startedAt 等字段）；无状态时返回 $null
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-WorkflowRunState {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir
    )

    [string]$StatePath = Join-Path -Path $ProjectDir -ChildPath '.ipap-run.json'
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        return $null
    }

    try {
        [string]$RawJson = Get-Content -LiteralPath $StatePath -Raw -Encoding utf8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($RawJson)) {
            return $null
        }

        return ($RawJson | ConvertFrom-Json)
    }
    catch {
        # 状态文件损坏时按「没有状态」处理，避免因为一个坏文件无法重新跑
        Write-LogEntry -Level Warning -Message "运行状态文件无法解析，按全量处理: $StatePath"
        return $null
    }
}
