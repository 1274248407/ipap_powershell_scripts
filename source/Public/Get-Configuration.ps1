<#
.SYNOPSIS
    获取配置实例
.DESCRIPTION
    获取全局配置实例。如果已存在配置实例且未指定新的 ProjectRoot，则返回现有实例。
    否则创建新的配置实例并缓存到全局变量中。
.PARAMETER ProjectRoot
    项目根目录路径（可选）
.EXAMPLE
    # 获取已初始化的配置实例
    $config = Get-Configuration

    # 使用指定路径初始化配置
    $config = Get-Configuration -ProjectRoot 'D:\Projects\MyProject'
.EXAMPLE
    # 通过管道指定路径
    'D:\Projects\MyProject' | Get-Configuration
.INPUTS
    string
.OUTPUTS
    IPAPConfiguration
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-Configuration
{
    [CmdletBinding()]
    [OutputType('IPAPConfiguration')]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$ProjectRoot
    )

    process
    {
        if ($script:IPAPConfigInstance -and [string]::IsNullOrWhiteSpace($ProjectRoot))
        {
            return $script:IPAPConfigInstance
        }

        $Root = $ProjectRoot
        if ([string]::IsNullOrWhiteSpace($Root))
        {
            if ($script:IPAPConfigInstance)
            {
                $Root = $script:IPAPConfigInstance.Paths.ProjectRoot
            }
            else
            {
                throw [System.InvalidOperationException]::new('ProjectRoot 未指定，且配置实例未初始化')
            }
        }

        $script:IPAPConfigInstance = [IPAPConfiguration]::Load($Root)
        return $script:IPAPConfigInstance
    }
}

