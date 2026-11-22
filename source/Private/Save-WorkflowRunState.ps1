<#
.SYNOPSIS
    写入项目的运行状态标记
.DESCRIPTION
    在项目根目录写 `.ipap-run.json`，记录本次处理使用的等级、倍数、模型与页面数量。
    它的作用是「标记本次运行尚未完成」：流程正常收尾时由 Remove-WorkflowRunState 删除，
    中途失败或进程被打断则会留下，下次启动据此自动续跑并核对参数是否变化。
.PARAMETER ProjectDir
    项目根目录。
.PARAMETER ProjectLevel
    项目统一等级（0/1/2）。
.PARAMETER RealCuganScale
    Real-CUGAN 的放大倍数。
.PARAMETER ModelSelect
    模型名称（models-se / models-pro / models-nose）。
.PARAMETER TextCount
    有文字图数量。
.PARAMETER NonTextCount
    无文字图数量。
.EXAMPLE
    Save-WorkflowRunState -ProjectDir $projectDir -ProjectLevel 1 -RealCuganScale 2 -ModelSelect 'models-se' -TextCount 731 -NonTextCount 630
.INPUTS
    无
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Save-WorkflowRunState {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2)]
        [int]$ProjectLevel,

        [Parameter(Mandatory = $true)]
        [int]$RealCuganScale,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ModelSelect,

        [Parameter(Mandatory = $true)]
        [int]$TextCount,

        [Parameter(Mandatory = $true)]
        [int]$NonTextCount
    )

    [string]$StatePath = Join-Path -Path $ProjectDir -ChildPath '.ipap-run.json'
    [PSCustomObject]$State = [PSCustomObject]@{
        status         = 'running'
        projectLevel   = $ProjectLevel
        realCuganScale = $RealCuganScale
        modelSelect    = $ModelSelect
        textCount      = $TextCount
        nonTextCount   = $NonTextCount
        startedAt      = (Get-Date).ToString('o')
    }

    $State | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $StatePath -Encoding utf8 -ErrorAction Stop
}
