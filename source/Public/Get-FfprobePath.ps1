<#
.SYNOPSIS
    获取 FFprobe 可执行文件路径
.DESCRIPTION
    从配置实例读取 FFprobe 路径；缺失时记录 Error 日志并抛出 FileNotFoundException。
    配置实例本身已完成「配置路径 > PATH 环境变量」的回退，本函数不再重复回退。
.EXAMPLE
    Get-FfprobePath
    获取 FFprobe 可执行文件路径。
.INPUTS
    无
.OUTPUTS
    string（缺失时抛 FileNotFoundException，不返回 $null）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-FfprobePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 从配置获取 FFprobe 路径
    $FfprobePath = (Get-Configuration).Tools.FfprobeExePath
    if ($FfprobePath) {
        return $FfprobePath
    }

    # 记录错误现场后显式抛出强类型异常，中断本函数（Write-LogEntry 为纯日志函数）
    $ErrorMessage = '未找到 FFprobe'
    Write-LogEntry -Level Error -Message $ErrorMessage
    throw [System.IO.FileNotFoundException]::new($ErrorMessage)
}

