<#
.SYNOPSIS
    分析单张图片的质量分级
.DESCRIPTION
    通过 FFprobe 获取图片分辨率，并通过 FFmpeg 标准 edgedetect 滤镜提取边缘图，
    以其 PNG 大小作为高频细节指标 YDIF（KB）。
    根据分辨率和 YDIF 值返回 Level 0（高清跳过）、Level 1（FFmpeg 锐化）、Level 2（Real-CUGAN）。
    外部进程调用通过 InvokeFfprobe / InvokeFfmpeg 注入，默认直接调用真实可执行文件；
    该接缝让单元测试无需依赖真实 ffmpeg 即可覆盖全部成功、失败与异常分支。
.PARAMETER Index
    图片在原始列表中的索引，用于外层恢复顺序。
.PARAMETER Image
    图片文件对象，必须包含 FullName 属性。
.PARAMETER FfprobePath
    FFprobe 可执行文件路径。
.PARAMETER FfmpegPath
    FFmpeg 可执行文件路径。
.PARAMETER HighDetailThreshold
    Level 0 的高细节阈值（KB），默认 6.0。
.PARAMETER MediumDetailThreshold
    Level 1 的中细节阈值（KB），默认 3.0。
.PARAMETER InvokeFfprobe
    FFprobe 调用适配器，返回包含 Output 与 ExitCode 的对象；默认直接调用可执行文件。
.PARAMETER InvokeFfmpeg
    FFmpeg 调用适配器，返回包含 Output 与 ExitCode 的对象；默认直接调用可执行文件。
.EXAMPLE
    Get-ImageLevelForImage -Index 0 -Image $image -FfprobePath $ffprobe -FfmpegPath $ffmpeg
.INPUTS
    无
.OUTPUTS
    PSCustomObject
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-ImageLevelForImage {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [object]$Image,

        [Parameter(Mandatory = $true)]
        [string]$FfprobePath,

        [Parameter(Mandatory = $true)]
        [string]$FfmpegPath,

        [double]$HighDetailThreshold = 6.0,

        [double]$MediumDetailThreshold = 3.0,

        # 默认适配器：直接调用 FFprobe，返回原始输出与退出码
        [scriptblock]$InvokeFfprobe = {
            param([string]$Path, [string[]]$Arguments)
            [object]$output = & $Path @Arguments 2>&1
            return [PSCustomObject]@{ Output = $output; ExitCode = $LASTEXITCODE }
        },

        # 默认适配器：直接调用 FFmpeg，返回原始输出与退出码
        [scriptblock]$InvokeFfmpeg = {
            param([string]$Path, [string[]]$Arguments)
            $null = & $Path @Arguments 2>&1
            return [PSCustomObject]@{ Output = $null; ExitCode = $LASTEXITCODE }
        }
    )

    [int]$level = 0
    [int]$longEdge = 0
    [double]$ydif = 0.0
    [string]$detailError = ''
    [string]$tempDir = ''

    try {
        # 1. 通过 FFprobe 获取分辨率
        [string[]]$ffprobeArgs = @(
            '-v', 'error',
            '-select_streams', 'v:0',
            '-show_entries', 'stream=width,height',
            '-of', 'csv=s=x:p=0',
            $Image.FullName
        )
        [object]$probeResult = & $InvokeFfprobe $FfprobePath $ffprobeArgs

        if ($probeResult.ExitCode -eq 0 -and $probeResult.Output -match '(\d+)x(\d+)') {
            [int]$width = [int]$Matches[1]
            [int]$height = [int]$Matches[2]
            $longEdge = [math]::Max($width, $height)

            # 2. 通过 FFmpeg 标准 edgedetect 提取边缘图，用 PNG 大小衡量高频细节
            $tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            [string]$tempOutput = Join-Path $tempDir 'output.png'

            # 标准滤镜，不依赖自定义 FFmpeg 构建；边缘越密集，输出 PNG 越大
            [string[]]$ffmpegArgs = @(
                '-i', $Image.FullName,
                '-vf', 'format=gray,edgedetect',
                '-frames:v', '1',
                '-y', $tempOutput
            )
            [object]$ffmpegResult = & $InvokeFfmpeg $FfmpegPath $ffmpegArgs

            # 细节越丰富，临时 PNG 越大，YDIF 越大
            if ($ffmpegResult.ExitCode -eq 0 -and (Test-Path -LiteralPath $tempOutput)) {
                $fileInfo = Get-Item -LiteralPath $tempOutput
                $ydif = [math]::Round($fileInfo.Length / 1KB, 2)
            }
            else {
                $ydif = 5.0  # 默认中间值
                $detailError = 'edgedetect 输出缺失或 FFmpeg 退出码非 0'
            }
        }
        else {
            $ydif = 5.0  # 默认中间值
            $detailError = 'FFprobe 未能解析出分辨率'
        }
    }
    catch {
        $ydif = 5.0  # 出错时使用默认值
        $detailError = $PSItem.Exception.Message
    }
    finally {
        # 成功、失败、异常三种路径都清理临时目录，避免 %TEMP% 泄漏
        if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. 根据分辨率和 YDIF 分级（阈值为可配置的 KB 值）
    # Level 0: 长边 >= 1920 且 YDIF >= HighDetailThreshold
    # Level 1: 长边 >= 1100 或 YDIF >= MediumDetailThreshold
    # Level 2: 其他情况
    if ($longEdge -ge 1920 -and $ydif -ge $HighDetailThreshold) {
        $level = 0
    }
    elseif ($longEdge -ge 1100 -or $ydif -ge $MediumDetailThreshold) {
        $level = 1
    }
    else {
        $level = 2
    }

    return [PSCustomObject]@{
        Index       = $Index
        Image       = $Image
        Level       = $level
        LongEdge    = $longEdge
        YDIF        = $ydif
        DetailError = $detailError
    }
}
