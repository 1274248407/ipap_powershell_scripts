<#
.SYNOPSIS
    重置配置实例
.DESCRIPTION
    清除全局配置实例，强制下次调用 Get-Configuration 时重新加载配置。
.EXAMPLE
    Reset-Configuration
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Reset-Configuration
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param()

    if ($PSCmdlet.ShouldProcess('全局配置实例', '重置'))
    {
        $script:IPAPConfigInstance = $null
    }
}

