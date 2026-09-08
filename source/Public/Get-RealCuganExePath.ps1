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
    param()

    # 从配置获取 Real-CUGAN 路径
    $RealCuganPath = (Get-Configuration).Tools.RealCuganExePath
    if ($RealCuganPath)
    {
        return $RealCuganPath
    }

    Write-ErrorLog '未找到 Real-CUGAN'
}

