<#
.SYNOPSIS
    从图片集合中筛选出还没有有效产物的页面
.DESCRIPTION
    纯 IO 辅助函数：对每张图片检查 OutputDir 下是否存在同名、同格式且大小大于 0 的产物。
    用于「续跑」——上次失败后重跑时只处理缺失页，避免整批重做。
    判定口径与 Test-UpscaleResult 一致：产物必须存在、扩展名匹配、且不是 0 字节残缺文件。
.PARAMETER Images
    待检查的图片文件对象数组，需包含 Name 或 FullName。
.PARAMETER OutputDir
    产物目录。
.PARAMETER OutputFormat
    期望的产物扩展名（jpg / png / webp）。
.EXAMPLE
    $pending = @(Get-PendingImage -Images $images -OutputDir $preprocessingDir -OutputFormat 'webp')
.INPUTS
    无
.OUTPUTS
    与输入同类型对象（可能为空）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-PendingImage {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = '输入对象类型由调用方决定（图片信息对象），[OutputType] 仅表达「返回同类型元素」')]
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [array]$Images,

        [Parameter(Mandatory = $true)]
        [string]$OutputDir,

        [Parameter(Mandatory = $true)]
        [ValidateSet('jpg', 'png', 'webp')]
        [string]$OutputFormat
    )

    foreach ($image in $Images) {
        [string]$baseName = [System.IO.Path]::GetFileNameWithoutExtension($image.Name ?? $image.FullName)
        [string]$expectedPath = Join-Path -Path $OutputDir -ChildPath "$baseName.$OutputFormat"

        # 产物不存在 → 待处理
        if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
            $image
            continue
        }

        # 0 字节产物（上次被中断或编码器失败）→ 视为待处理，避免把坏文件当成已完成
        if ((Get-Item -LiteralPath $expectedPath).Length -le 0) {
            $image
        }
    }
}
