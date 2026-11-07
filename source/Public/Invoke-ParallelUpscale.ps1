<#
.SYNOPSIS
    并行高清化处理图片
.DESCRIPTION
    使用 PowerShell 的并行处理功能同时高清化多张图片，支持 Real-CUGAN AI 超分和 FFmpeg 锐化两种引擎。
    返回处理结果统计（成功数和失败数）。
.PARAMETER Images
    (array, Mandatory) 图片文件对象数组。
    （适用于所有参数集）
.PARAMETER OutputDir
    (string, Mandatory) 输出目录。
    （适用于所有参数集）
.PARAMETER Engine
    (string, 有效值: RealCugan, FFmpeg) 使用的处理引擎，默认为 RealCugan。
    （适用于所有参数集）
.PARAMETER MaxWorkers
    (int) 最大并发数，默认为 8。
    （适用于所有参数集）
.PARAMETER Scale
    (int) 缩放比例，默认为 2。
    （适用于所有参数集）
.PARAMETER ModelPath
    (string) 模型路径，默认为 "models-se"。
    （适用于所有参数集）
.PARAMETER OutputFormat
    (string) 输出格式，默认为 "webp"。
    （适用于所有参数集）
.EXAMPLE
    Invoke-ParallelUpscale -Images $images -OutputDir "output" -MaxWorkers 4
    使用 4 个并发处理图片。
.INPUTS
    无
.OUTPUTS
    hashtable (包含 SuccessCount, FailedCount)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Invoke-ParallelUpscale {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Images,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [ValidateSet('RealCugan', 'FFmpeg')]
        [string]$Engine = 'RealCugan',
        [ValidateRange(1, 32)]
        [int]$MaxWorkers = 8,
        [ValidateRange(1, 4)]
        [int]$Scale = 2,
        [ValidateRange(-1, 3)]
        [int]$NoiseLevel = 0,
        [ValidateSet('models-se', 'models-pro', 'models-nose')]
        [string]$ModelPath = 'models-se',
        [ValidateSet('jpg', 'png', 'webp')]
        [string]$OutputFormat = 'webp',
        [ValidateRange(32, 1024)]
        [int]$TileSize = 128
    )

    # 引擎路径解析（缺失时 Get-*Path 内部直接抛出终止错误；每个引擎只解析一次）
    [string]$ExePath = $Engine -eq 'FFmpeg' ? (Get-FfmpegPath) : (Get-RealCuganExePath)

    Write-LogEntry -Level Info -Message "开始并行图片处理，引擎: $Engine, 并发数: $MaxWorkers"

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # 在主 runspace 构造每张图的输出路径与参数（纯函数，可在单测中直接验证）
    $jobs = foreach ($image in $Images) {
        [string]$fileName = [System.IO.Path]::GetFileNameWithoutExtension($image.FullName)
        [string]$outputPath = Join-Path $OutputDir "${fileName}.${OutputFormat}"
        [string[]]$arguments = if ($Engine -eq 'RealCugan') {
            Get-RealCuganArgument -ImagePath $image.FullName -OutputPath $outputPath `
                -NoiseLevel $NoiseLevel -Scale $Scale -TileSize $TileSize `
                -ModelPath $ModelPath -OutputFormat $OutputFormat
        }
        else {
            Get-FfmpegArgument -ImagePath $image.FullName -OutputPath $outputPath -OutputFormat $OutputFormat
        }

        [PSCustomObject]@{
            Image      = $image
            OutputPath = $outputPath
            Arguments  = $arguments
        }
    }

    # 并行 runspace 不继承模块函数，因此把单图执行器序列化后注入
    [string]$WorkerSource = ${function:Invoke-UpscaleProcess}.ToString()
    $results = $jobs | ForEach-Object -Parallel {
        [scriptblock]$worker = [scriptblock]::Create($using:WorkerSource)
        & $worker -Image $PSItem.Image -OutputPath $PSItem.OutputPath -Arguments $PSItem.Arguments `
            -Engine $using:Engine -ExePath $using:ExePath
    } -ThrottleLimit $MaxWorkers

    [PSCustomObject]$counts = Write-UpscaleSummary -Results @($results)

    Write-LogEntry -Level Info -Message "并行处理完成，成功: $($counts.SuccessCount), 失败: $($counts.FailedCount)"

    return @{ SuccessCount = $counts.SuccessCount; FailedCount = $counts.FailedCount }
}
