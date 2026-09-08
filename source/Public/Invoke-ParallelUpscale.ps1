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

function Invoke-ParallelUpscale
{
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
        [int]$MaxWorkers = 0,
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

    # 校验引擎对应的可执行文件是否可用（缺失时 Get-*Path 内部直接抛出终止错误）
    if ($Engine -eq 'RealCugan')
    {
        $null = Get-RealCuganExePath
    }

    # FFmpeg 引擎路径解析（缺失时 Get-FfmpegPath 内部直接抛出终止错误）
    $FfmpegPath = $null
    if ($Engine -eq 'FFmpeg')
    {
        $FfmpegPath = Get-FfmpegPath
    }

    Write-InfoLog "开始并行图片处理，引擎: $Engine, 并发数: $MaxWorkers"

    if (-not (Test-Path -LiteralPath $OutputDir))
    {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $successCount = 0
    $failedCount = 0

    if ($Engine -eq 'RealCugan')
    {
        # Real-CUGAN 引擎：AI 超分（Level 2）
        $realCuganExePath = Get-RealCuganExePath

        $Images | ForEach-Object -Parallel {
            $image = $PSItem
            $outputDir = $using:OutputDir
            $scale = $using:Scale
            $noiseLevel = $using:NoiseLevel
            $modelPath = $using:ModelPath
            $outputFormat = $using:OutputFormat
            $tileSize = $using:TileSize
            $realCuganExePath = $using:realCuganExePath

            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($image.FullName)
            $outputPath = Join-Path $outputDir "${fileName}.${outputFormat}"

            try
            {
                $realCuganArgs = @(
                    '-i', $image.FullName,
                    '-o', $outputPath,
                    '-n', $noiseLevel,
                    '-s', $scale,
                    '-t', $tileSize,
                    '-m', $modelPath,
                    '-f', $outputFormat
                )

                & $realCuganExePath @realCuganArgs

                if (Test-Path -LiteralPath $outputPath)
                {
                    return @{ Success = $true; Image = $image.Name }
                }
                else
                {
                    return @{ Success = $false; Image = $image.Name }
                }
            }
            catch
            {
                return @{ Success = $false; Image = $image.Name; Error = $PSItem.Exception.Message }
            }
        } -ThrottleLimit $MaxWorkers | ForEach-Object {
            if ($PSItem.Success)
            {
                Write-InfoLog "图片处理成功: $($PSItem.Image)"
                $successCount++
            }
            else
            {
                # 单张图片失败不中断批次，降级为警告日志并计入失败数
                Write-WarningLog "图片处理失败: $($PSItem.Image)"
                $failedCount++
            }
        }
    }
    else
    {
        # FFmpeg 引擎：Lanczos 放大 + Unsharp Mask 锐化（Level 1）
        $FfmpegPath = Get-FfmpegPath
        $Images | ForEach-Object -Parallel {
            $image = $PSItem
            $outputDir = $using:OutputDir
            $outputFormat = $using:OutputFormat
            $ffmpegPath = $using:FfmpegPath

            # 将输出格式映射为 FFmpeg 编码器名称
            $codecMap = @{ 'jpg' = 'mjpeg'; 'jpeg' = 'mjpeg'; 'png' = 'png'; 'webp' = 'libwebp' }
            $codec = $codecMap[$outputFormat.ToLower()]
            # 默认输出webp格式
            if (-not $codec) { $codec = 'libwebp' }

            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($image.FullName)
            $outputPath = Join-Path $outputDir "${fileName}.${outputFormat}"

            try
            {
                # Lanczos 放大 1.2 倍 + USM 锐化
                # 1. 基础输入输出参数
                # -i $image.FullName: 指定输入文件。-i 代表 input，即原始图片的完整路径。
                # -y $outputPath: -y 代表默认覆盖，如果输出路径已有同名文件直接覆盖不卡住脚本；$outputPath 是最终处理完的图片保存路径。
                # 2. 核心滤镜链参数 (-vf)
                # -vf 后面的字符串是视频滤镜链，两个滤镜用逗号 , 分隔，按从左到右顺序执行：

                # scale=iw*1.2:ih*1.2:flags=lanczos:
                # 放大图片。

                # iw*1.2:ih*1.2：将宽度 和高度 分别乘以 1.2，即放大 1.2 倍。
                # flags=lanczos：指定使用 Lanczos 缩放算法。这是一种高质量的插值算法，能在放大图片时最大程度保留细节，减少锯齿和模糊。
                # unsharp=5:5:1.0:
                # 锐化滤镜（USM 锐化）。图片放大后通常会显得发虚，需要加锐化找回清晰感。

                # 前两个 5:5：代表锐化矩阵的宽度和高度（5x5），决定锐化影响的像素范围。
                # 最后的 1.0：代表锐化强度。数值越大越锐利，但过高会产生白边噪点，1.0 是一个适中的值。
                # 3. 编码与质量控制参数
                # -c:v $codec: 指定视频编码器。-c:v 是 codec video 的缩写。代码中会根据你选择的输出格式动态映射，比如输出 webp 就用 libwebp，输出 jpg 就用 mjpeg。
                # -quality 95: 设置输出质量为 95。对于 webp 或 jpg 等有损压缩格式，95 代表极高的画质（几乎无损），避免二次压缩导致画质严重下降。
                $ffmpegArgs = @(
                    '-i', $image.FullName,
                    '-vf', 'scale=iw*1.2:ih*1.2:flags=lanczos,unsharp=5:5:1.0',
                    '-c:v', $codec,
                    '-quality', '95',
                    '-y', $outputPath
                )
                $null = & $ffmpegPath @ffmpegArgs 2>&1

                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outputPath))
                {
                    return @{ Success = $true; Image = $image.Name }
                }
                else
                {
                    return @{ Success = $false; Image = $image.Name }
                }
            }
            catch
            {
                return @{ Success = $false; Image = $image.Name; Error = $PSItem.Exception.Message }
            }
        } -ThrottleLimit $MaxWorkers | ForEach-Object {
            if ($PSItem.Success)
            {
                Write-InfoLog "图片处理成功: $($PSItem.Image)"
                $successCount++
            }
            else
            {
                # 单张图片失败不中断批次，降级为警告日志并计入失败数
                Write-WarningLog "图片处理失败: $($PSItem.Image)"
                $failedCount++
            }
        }
    }

    Write-InfoLog "并行处理完成，成功: $successCount, 失败: $failedCount"

    return @{ SuccessCount = $successCount; FailedCount = $failedCount }
}

