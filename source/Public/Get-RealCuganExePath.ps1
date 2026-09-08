<#
.SYNOPSIS
    获取 Real-CUGAN 可执行文件路径
.DESCRIPTION
    从配置实例读取 Real-CUGAN 路径。
.EXAMPLE
    Get-RealCuganExePath
    获取 Real-CUGAN 可执行文件路径。
.INPUTS
    无
.OUTPUTS
    string 或 $null
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-RealCuganExePath
{
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 从配置获取 Real-CUGAN 路径
    $RealCuganPath = (Get-Configuration).Tools.RealCuganExePath
    if ($RealCuganPath)
    {
        return $RealCuganPath
    }

    # 记录错误现场后显式抛出强类型异常，中断本函数（Write-LogEntry 为纯日志函数）
    $ErrorMessage = '未找到 Real-CUGAN'
    Write-LogEntry -Level Error -Message $ErrorMessage
    throw [System.IO.FileNotFoundException]::new($ErrorMessage)
}

