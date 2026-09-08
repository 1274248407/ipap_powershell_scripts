<#
.SYNOPSIS
    获取 FFmpeg 可执行文件路径
.DESCRIPTION
    从配置实例读取 FFmpeg 路径，若配置路径不存在则回退到 PATH 环境变量。
.EXAMPLE
    Get-FfmpegPath
    获取 FFmpeg 可执行文件路径。
.INPUTS
    无
.OUTPUTS
    string 或 $null
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-FfmpegPath
{
    [CmdletBinding()]
    param()

    # 从配置获取 FFmpeg 路径
    $FfmpegPath = (Get-Configuration).Tools.FfmpegExePath
    if ($FfmpegPath)
    {
        return $FfmpegPath
    }

    Write-ErrorLog '未找到 FFmpeg'
}

