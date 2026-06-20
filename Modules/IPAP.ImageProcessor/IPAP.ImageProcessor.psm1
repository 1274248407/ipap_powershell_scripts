<#
.SYNOPSIS
    IPAP 工作流图片处理模块
.DESCRIPTION
    提供图片分析、高清化处理和并行处理功能。
#>

# ImageProcessor 模块依赖 IPAP.Core，IPAP.Core 由 Main.ps1 统一导入
# 不需要重复导入 PoShLog 和 IPAP.Core

Export-ModuleMember

<#
.SYNOPSIS
    分析图片目录并计算平均文件大小
.DESCRIPTION
    遍历指定目录中的图片文件，计算总大小和平均大小，并按自然顺序排序。
    若目录不存在则记录错误日志并返回空结果。
.PARAMETER SourceDir
    (string, Mandatory) 源图片目录路径。
    （适用于所有参数集）
.EXAMPLE
    Get-ImageInfo -SourceDir "C:\Images"
    分析 C:\Images 目录中的图片文件。
.INPUTS
    无
.OUTPUTS
    hashtable (包含 Images, TotalSize, AverageSize, Count)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-ImageInfo
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceDir
    )

    Write-InfoLog "正在分析图片目录: $SourceDir"

    if (-not (Test-Path -LiteralPath $SourceDir))
    {
        Write-ErrorLog "源目录不存在: $SourceDir"
        return @{ Images = @(); TotalSize = 0; AverageSize = 0; Count = 0 }
    }

    $images = @()
    $totalSize = 0
    $count = 0

    Get-ChildItem -LiteralPath $SourceDir -File | ForEach-Object {
        if ($Global:SupportedImageFormats -contains $PSItem.Extension.ToLower())
        {
            $images += $PSItem
            $totalSize += $PSItem.Length
            $count++
        }
    }

    $images = $images | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name }

    $averageSize = 0
    if ($count -gt 0)
    {
        $averageSize = $totalSize / 1024 / $count
    }

    Write-InfoLog "发现 $count 张图片，总大小: $([math]::Round($totalSize / 1024 / 1024, 2)) MB，平均大小: $([math]::Round($averageSize, 2)) KB"

    return @{
        Images      = $images
        TotalSize   = $totalSize
        AverageSize = $averageSize
        Count       = $count
    }
}

<#
.SYNOPSIS
    判断是否需要高清化处理
.DESCRIPTION
    根据平均文件大小判断是否需要进行图片高清化处理，阈值为 1000KB。
.PARAMETER AverageSize
    (double, Mandatory) 平均文件大小（KB）。
    （适用于所有参数集）
.EXAMPLE
    Test-NeedUpscale -AverageSize 500
    平均文件大小小于 1000KB，返回 $true。
.EXAMPLE
    Test-NeedUpscale -AverageSize 1500
    平均文件大小大于等于 1000KB，返回 $false。
.INPUTS
    double
.OUTPUTS
    bool
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Test-NeedUpscale
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [Nullable[double]]$AverageSize
    )

    if ($null -eq $AverageSize)
    {
        throw [System.ArgumentNullException]::new('AverageSize', '平均文件大小不能为 null')
    }

    $threshold = 1000

    if ($AverageSize -lt $threshold)
    {
        Write-InfoLog "平均文件大小 $([math]::Round($AverageSize, 2)) KB < $threshold KB，需要高清化"
        return $true
    }
    else
    {
        Write-InfoLog "平均文件大小 $([math]::Round($AverageSize, 2)) KB >= $threshold KB，跳过高清化"
        return $false
    }
}

<#
.SYNOPSIS
    分析图片质量分级
.DESCRIPTION
    通过 FFprobe 获取图片分辨率，并通过 FFmpeg 去网点提取高频细节 YDIF 值。
    根据分辨率和 YDIF 值将图片分为三个级别：Level 0（高清跳过）、Level 1（轻度模糊，FFmpeg 锐化）、Level 2（重度模糊，Real-CUGAN AI 超分）。
.PARAMETER Images
    (array, Mandatory) 图片文件对象数组，每个对象需要包含 FullName 属性。
    （适用于所有参数集）
.EXAMPLE
    Get-ImageLevel -Images $images
    分析图片数组的质量分级。
.INPUTS
    array
.OUTPUTS
    PSCustomObject[] (每个对象包含 Image, Level, LongEdge, YDIF 属性)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-ImageLevel
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Images
    )

    # 获取 FFprobe 和 FFmpeg 路径（从配置读取，fallback 到 PATH）
    $FfprobePath = Get-FfprobePath
    $FfmpegPath = Get-FfmpegPath

    if (-not $FfprobePath -or -not $FfmpegPath)
    {
        Write-ErrorLog 'FFmpeg/FFprobe 未找到，无法进行图片分级分析'
        # 所有图片降级为 Level 2（需要 Real-CUGAN 处理）
        return $Images | ForEach-Object {
            [PSCustomObject]@{ Image = $PSItem; Level = 2; LongEdge = 0; YDIF = 0.0 }
        }
    }

    Write-InfoLog "开始分析 $($Images.Count) 张图片的质量分级..."

    # 并行分析所有图片
    $results = $Images | ForEach-Object -Parallel {
        $image = $PSItem
        $ffprobePath = $using:FfprobePath
        $ffmpegPath = $using:FfmpegPath

        $level = 0
        $longEdge = 0
        $ydif = 0.0

        try
        {
            # 1. 通过 FFprobe 获取分辨率
            $ffprobeArgs = @('-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'csv=s=x:p=0', $image.FullName)
            $ffprobeOut = & $ffprobePath @ffprobeArgs 2>&1

            if ($LASTEXITCODE -eq 0 -and $ffprobeOut -match '(\d+)x(\d+)')
            {
                $width = [int]$Matches[1]
                $height = [int]$Matches[2]
                $longEdge = [math]::Max($width, $height)

                # 2. 通过 FFmpeg 去网点提取 YDIF（高频细节能量）
                $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                $tempOutput = Join-Path $tempDir 'output.png'

                $ffmpegArgs = @('-i', $image.FullName, '-vf', 'format=gray,dxpostsrc=h=8:v=0:sh=1:x=0:y=0,dxpostdst=h=8:v=0:sh=1:x=1:y=0,dynedgel=28,bmstools=p=3', '-frames:v', '1', '-y', $tempOutput)
                $null = & $ffmpegPath @ffmpegArgs 2>&1

                if ($LASTEXITCODE -eq 0 -and (Test-Path $tempOutput))
                {
                    $fileInfo = Get-Item $tempOutput
                    $fileSizeKB = $fileInfo.Length / 1KB
                    $ydif = [math]::Round($fileSizeKB, 2)

                    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                else
                {
                    $ydif = 5.0  # 默认中间值
                }
            }
            else
            {
                $ydif = 5.0  # 默认中间值
            }
        }
        catch
        {
            $ydif = 5.0  # 出错时使用默认值
        }

        # 3. 根据分辨率和 YDIF 分级
        # Level 0: 长边 >= 1920 且 YDIF >= 6.0 -> 高清，跳过
        # Level 1: 长边 >= 1100 或 YDIF >= 3.0 -> 中等模糊，FFmpeg 锐化
        # Level 2: 其他情况 -> 重度模糊，需要 Real-CUGAN
        if ($longEdge -ge 1920 -and $ydif -ge 6.0)
        {
            $level = 0
        }
        elseif ($longEdge -ge 1100 -or $ydif -ge 3.0)
        {
            $level = 1
        }
        else
        {
            $level = 2
        }

        [PSCustomObject]@{
            Image    = $image
            Level    = $level
            LongEdge = $longEdge
            YDIF     = $ydif
        }
    } -ThrottleLimit 8

    Write-InfoLog "图片分级分析完成: $($results.Count) 张"

    $level0Count = @($results | Where-Object { $_.Level -eq 0 }).Count
    $level1Count = @($results | Where-Object { $_.Level -eq 1 }).Count
    $level2Count = @($results | Where-Object { $_.Level -eq 2 }).Count
    Write-InfoLog "分级结果 - Level 0 (高清跳过): $level0Count, Level 1 (FFmpeg): $level1Count, Level 2 (Real-CUGAN): $level2Count"

    return $results
}

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

    # 检查引擎对应的可执行文件是否可用
    if ($Engine -eq 'RealCugan' -and -not $Global:RealCuganExePath)
    {
        Write-ErrorLog 'realcugan-ncnn-vulkan.exe 未找到，无法进行高清化处理'
        return @{ SuccessCount = 0; FailedCount = $Images.Count }
    }

    if ($Engine -eq 'FFmpeg')
    {
        $FfmpegPath = Get-FfmpegPath
        if (-not $FfmpegPath)
        {
            Write-ErrorLog 'FFmpeg 未找到，无法进行 FFmpeg 高清化处理'
            return @{ SuccessCount = 0; FailedCount = $Images.Count }
        }
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
        $Images | ForEach-Object -Parallel {
            $image = $PSItem
            $outputDir = $using:OutputDir
            $scale = $using:Scale
            $noiseLevel = $using:NoiseLevel
            $modelPath = $using:ModelPath
            $outputFormat = $using:OutputFormat
            $tileSize = $using:TileSize
            $realCuganExePath = $using:Global:RealCuganExePath

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
                Write-ErrorLog "图片处理失败: $($PSItem.Image)"
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
            if (-not $codec) { $codec = 'mjpeg' }

            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($image.FullName)
            $outputPath = Join-Path $outputDir "${fileName}.${outputFormat}"

            try
            {
                # Lanczos 放大 1.2 倍 + USM 锐化
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
                Write-ErrorLog "图片处理失败: $($PSItem.Image)"
                $failedCount++
            }
        }
    }

    Write-InfoLog "并行处理完成，成功: $successCount, 失败: $failedCount"

    return @{ SuccessCount = $successCount; FailedCount = $failedCount }
}

Export-ModuleMember -Function @(
    'Get-ImageInfo',
    'Test-NeedUpscale',
    'Get-ImageLevel',
    'Invoke-ParallelUpscale'
)
