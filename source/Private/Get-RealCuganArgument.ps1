<#
.SYNOPSIS
    构造 Real-CUGAN 命令行参数
.DESCRIPTION
    纯函数：根据输入输出路径与超分参数，返回 Real-CUGAN 可执行文件所需的参数数组。
    不调用外部进程，便于单元测试精确断言参数顺序与取值。
.PARAMETER ImagePath
    输入图片完整路径。
.PARAMETER OutputPath
    输出图片完整路径。
.PARAMETER NoiseLevel
    降噪级别。
.PARAMETER Scale
    放大倍数。
.PARAMETER TileSize
    分块大小。
.PARAMETER ModelPath
    模型目录。
.PARAMETER OutputFormat
    输出格式。
.EXAMPLE
    Get-RealCuganArgument -ImagePath 'a.png' -OutputPath 'b.webp' -NoiseLevel 0 -Scale 2 -TileSize 128 -ModelPath 'models-se' -OutputFormat 'webp'
.INPUTS
    无
.OUTPUTS
    string[]（Real-CUGAN 参数数组）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-RealCuganArgument {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [int]$NoiseLevel,

        [Parameter(Mandatory = $true)]
        [int]$Scale,

        [Parameter(Mandatory = $true)]
        [int]$TileSize,

        [Parameter(Mandatory = $true)]
        [string]$ModelPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputFormat
    )

    return [string[]]@(
        '-i', $ImagePath,
        '-o', $OutputPath,
        '-n', [string]$NoiseLevel,
        '-s', [string]$Scale,
        '-t', [string]$TileSize,
        '-m', $ModelPath,
        '-f', $OutputFormat
    )
}
