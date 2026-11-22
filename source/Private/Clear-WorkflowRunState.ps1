<#
.SYNOPSIS
    清理项目的运行状态标记
.DESCRIPTION
    流程正常收尾（产出校验通过）后调用，表示本次运行已完成。函数名用 Clear 而非 Remove：它清理的是本次运行自己的标记，不涉及用户数据。
    文件不存在时静默返回，不抛异常。
.PARAMETER ProjectDir
    项目根目录。
.EXAMPLE
    Clear-WorkflowRunState -ProjectDir $projectDir
.INPUTS
    无
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Clear-WorkflowRunState {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir
    )

    [string]$StatePath = Join-Path -Path $ProjectDir -ChildPath '.ipap-run.json'
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        Remove-Item -LiteralPath $StatePath -Force
    }
}
