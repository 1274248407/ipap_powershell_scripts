<#
.SYNOPSIS
    获取 FFprobe 可执行文件路径
.DESCRIPTION
    从配置实例读取 FFprobe 路径，若配置路径不存在则回退到 PATH 环境变量。
.EXAMPLE
    Get-FfprobePath
    获取 FFprobe 可执行文件路径。
.INPUTS
    无
.OUTPUTS
    string 或 $null
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-FfprobePath
{
    [CmdletBinding()]
    param()

    # 从配置获取 FFprobe 路径
    $FfprobePath = (Get-Configuration).Tools.FfprobeExePath
    if ($FfprobePath)
    {
        return $FfprobePath
    }

    Write-ErrorLog '未找到 FFprobe'
}

