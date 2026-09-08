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
    PSCustomObject (每个对象包含 Image, Level, LongEdge, YDIF 属性，逐个输出)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-ImageLevel
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Images
    )

    # 获取 FFprobe 和 FFmpeg 路径（从配置读取，fallback 到 PATH；缺失时内部直接抛出终止错误）
    $FfprobePath = Get-FfprobePath
    $FfmpegPath = Get-FfmpegPath

    Write-LogEntry -Level Info -Message "开始分析 $($Images.Count) 张图片的质量分级..."



    # 并行分析所有图片（保留原始顺序）
    $indexedImages = for ($i = 0; $i -lt $Images.Count; $i++)
    {
        [PSCustomObject]@{ Index = $i; Image = $Images[$i] }
    }

    $results = $indexedImages | ForEach-Object -Parallel {
        $item = $PSItem
        $image = $item.Image
        $index = $item.Index
        $ffprobePath = $using:FfprobePath
        $ffmpegPath = $using:FfmpegPath

        $level = 0
        $longEdge = 0
        $ydif = 0.0

        try
        {
            # 1. 通过 FFprobe 获取分辨率
            # -v error: 设置日志级别为 error。FFprobe 默认会输出大量版本、元数据等冗余信息，设为 error 可以屏蔽这些干扰，只在出错时才打印信息，方便脚本解析输出。
            # -select_streams v:0: 选择第 0 个视频流（v 代表 Video）。因为某些文件可能包含多个流（如音频、字幕、封面图等），这确保我们只分析主视频/图片流。
            # -show_entries stream=width, height: 指定要显示的数据条目。这里告诉 FFprobe 只显示 stream（流）中的 width（宽）和 height（高）属性，忽略其他如编码格式、帧率等无关信息。
            # -of csv=s=x:p=0: 设置输出格式（-of 是 -output_format 的缩写）。csv 表示用逗号分隔格式：
            # s=x：设置分隔符为 x（默认是逗号），这样宽和高之间会用 x 连接。
            # p=0：不打印属性名前缀（默认会打印 width=1920, height=1080），设为 0 后只打印值。
            # 如果图片是 1920x1080，这行参数组合的输出结果就是纯净的 1920x1080，没有任何多余字符
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
                # 滤镜链说明（format=gray 为标准滤镜，其余四个为非标准自定义滤镜，需配合特定 FFmpeg 编译版本）
                # format=gray: 转为灰度图，去除颜色干扰，只保留亮度信息，为后续提取细节做准备。
                # dxpostsrc/dxpostdst: 非标准滤镜，FFmpeg 官方文档无记录。调整图像底层色彩/亮度参数，具体行为取决于所使用的 FFmpeg 编译版本。
                # dynedgel=28: 非标准边缘增强滤镜，FFmpeg 官方有 edgedetect 但无 dynedgel。动态提取并强化图像边缘轮廓，=28 为强度值。
                # bmstools=p=3: 非标准工具滤镜，FFmpeg 官方有 bm3d（去噪）但无 bmstools。对图像做最终格式化处理，p=3 为预设参数。
                $ffmpegArgs = @('-i', $image.FullName, '-vf', 'format=gray,dxpostsrc=h=8:v=0:sh=1:x=0:y=0,dxpostdst=h=8:v=0:sh=1:x=1:y=0,dynedgel=28,bmstools=p=3', '-frames:v', '1', '-y', $tempOutput)
                $null = & $ffmpegPath @ffmpegArgs 2>&1
                # 滤镜把图片变成黑白，并极力强化了边缘和细节。
                # 细节越丰富的图片，保存为 PNG 时压缩率越低，文件体积就越大。
                # 因此，临时输出的 PNG 文件越大（$fileSizeKB），说明原图的高频细节越多（$ydif 越大）。
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
            Index    = $index
            Image    = $image
            Level    = $level
            LongEdge = $longEdge
            YDIF     = $ydif
        }
    } -ThrottleLimit 8

    # 按原始索引排序恢复顺序
    $results = $results | Sort-Object -Property Index

    Write-LogEntry -Level Info -Message "图片分级分析完成: $($results.Count) 张"



    $level0Count = @($results | Where-Object { $PSItem.Level -eq 0 }).Count
    $level1Count = @($results | Where-Object { $PSItem.Level -eq 1 }).Count
    $level2Count = @($results | Where-Object { $PSItem.Level -eq 2 }).Count
    Write-LogEntry -Level Info -Message "分级结果 - Level 0 (高清跳过): $level0Count, Level 1 (FFmpeg): $level1Count, Level 2 (Real-CUGAN): $level2Count"

    return $results
}

