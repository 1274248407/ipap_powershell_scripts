<#
.SYNOPSIS
    将输出格式映射为 FFmpeg 编码器名称
.DESCRIPTION
    纯函数：jpg/jpeg 映射为 mjpeg，png 映射为 png，webp 映射为 libwebp；
    未知格式回退为 libwebp（与既有行为一致）。
.PARAMETER OutputFormat
    输出格式（大小写不敏感）。
.EXAMPLE
    Get-FfmpegCodec -OutputFormat 'webp'
.INPUTS
    无
.OUTPUTS
    string（FFmpeg 编码器名称）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-FfmpegCodec {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputFormat
    )

    [hashtable]$codecMap = @{
        'jpg'  = 'mjpeg'
        'jpeg' = 'mjpeg'
        'png'  = 'png'
        'webp' = 'libwebp'
    }

    [string]$codec = $codecMap[$OutputFormat.ToLowerInvariant()]
    # 未知格式回退为 webp 编码器（与既有并行块行为一致）
    return $codec ? $codec : 'libwebp'
}
