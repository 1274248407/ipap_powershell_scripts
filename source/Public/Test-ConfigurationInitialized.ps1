<#
.SYNOPSIS
    测试配置是否已初始化
.DESCRIPTION
    检查全局配置实例是否已初始化。
.EXAMPLE
    if (Test-ConfigurationInitialized) {
        Write-Host '配置已初始化'
    }
.OUTPUTS
    bool
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Test-ConfigurationInitialized
{
    [CmdletBinding()]
    param()

    return $null -ne $Global:IPAPConfigInstance
}

