<#
.SYNOPSIS
    构造 FFmpeg 放大锐化命令行参数
.DESCRIPTION
    纯函数：根据输入输出路径与输出格式，返回 FFmpeg 参数数组。
    默认滤镜链固定为 Lanczos 1.2 倍放大 + USM 锐化，编码器由 Get-FfmpegCodec 映射。
    参数含义：
    - -vf 'scale=iw*1.2:ih*1.2:flags=lanczos,unsharp=5:5:1.0'：
      scale 按 Lanczos 插值把宽高各放大 1.2 倍以保留细节、减少锯齿；
      unsharp=5:5:1.0 为亮度 USM 锐化（5x5 矩阵、强度 1.0），色度锐化保持默认 0，
      避免引入色彩噪点。指定 -NoResize 时不加该滤镜链，只做格式转换。
    - -c:v 编码器由输出格式映射（webp -> libwebp、jpg -> mjpeg、png -> png）。
    - -quality 由调用方传入（`[webp].quality`，默认 95），保证有损格式几乎无损，避免二次压缩掉画质。
    - -y 覆盖同名输出，批处理时不会卡在交互询问上。
.PARAMETER ImagePath
    输入图片完整路径。
.PARAMETER OutputPath
    输出图片完整路径。
.PARAMETER OutputFormat
    输出格式（jpg/png/webp）。
.PARAMETER NoResize
    只做格式转换，不放大也不锐化。用于 Level 0 的统一转码（尺寸保持不变）。
.PARAMETER Quality
    有损编码质量（ffmpeg -quality，0-100），来自 `[webp].quality`，默认 95。
.EXAMPLE
    Get-FfmpegArgument -ImagePath 'a.png' -OutputPath 'b.webp' -OutputFormat 'webp'
    构造「1.2 倍放大 + 锐化 + webp 编码」的参数。
.EXAMPLE
    Get-FfmpegArgument -ImagePath 'a.jpg' -OutputPath 'b.webp' -OutputFormat 'webp' -NoResize
    构造「仅转码为 webp、尺寸不变」的参数。
.INPUTS
    无
.OUTPUTS
    string[]（FFmpeg 参数数组）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-FfmpegArgument {
    [CmdletBinding()]
    [OutputType([string])]
    # 项目约定：[OutputType()] 声明元素类型而非集合类型；该规则按实际返回的 string[] 比对会误报，
    # 此处精确压制，其余源文件仍受 PSUseOutputTypeCorrectly 保护
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = '项目约定：[OutputType()] 声明元素类型；本函数返回 string[]，管道展开后为 string 流')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputFormat,

        [ValidateRange(0, 100)]
        [int]$Quality = 95,

        [switch]$NoResize
    )

    [string]$codec = Get-FfmpegCodec -OutputFormat $OutputFormat

    [System.Collections.Generic.List[string]]$arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.AddRange([string[]]@('-i', $ImagePath))

    # 纯转码只换容器/编码，不改变宽高；放大路径才加滤镜链
    if (-not $NoResize) {
        $arguments.AddRange([string[]]@('-vf', 'scale=iw*1.2:ih*1.2:flags=lanczos,unsharp=5:5:1.0'))
    }

    $arguments.AddRange([string[]]@('-c:v', $codec, '-quality', [string]$Quality, '-y', $OutputPath))

    return $arguments.ToArray()
}
