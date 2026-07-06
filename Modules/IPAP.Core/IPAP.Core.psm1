<#
.SYNOPSIS
    IPAP 工作流核心基础模块
.DESCRIPTION
    提供日志系统和通用工具函数。配置管理已迁移至 IPAP.Configuration 模块。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

# 导入 PoShLog 模块（如果存在）
$PoShLogPath = Join-Path $PSScriptRoot '..\..\Modules\PoShLog'
if (Test-Path -LiteralPath $PoShLogPath)
{
    Import-Module -Name $PoShLogPath -Force -Scope Global
}

<#
.SYNOPSIS
    生成自然排序键
.DESCRIPTION
    将文件名转换为自然排序键，实现数字在字符串中的自然排序。
    例如：file1.txt, file10.txt, file2.txt 会按数字大小排序。
.PARAMETER InputString
    (string, Mandatory) 输入字符串。
    （适用于所有参数集）
.EXAMPLE
    Get-NaturalSortKey -InputString "image10.png"
    生成自然排序键。
.INPUTS
    string
.OUTPUTS
    string
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-NaturalSortKey
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputString
    )

    # 使用正则分割字符串，捕获数字部分
    $parts = [regex]::Split($InputString, '(\d+)')

    # 过滤空字符串，并转换数字
    $result = $parts | Where-Object { -not [string]::IsNullOrEmpty($PSItem) } | ForEach-Object {
        if ($PSItem -match '^\d+$')
        {
            [int]$PSItem
        }
        else
        {
            $PSItem
        }
    }

    return $result
}

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
    return $null
}

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
    return $null
}

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
    return $null
}

<#
.SYNOPSIS
    获取支持的图片格式
.DESCRIPTION
    从配置实例读取支持的图片格式列表。
.EXAMPLE
    Get-SupportedImageFormat
    获取支持的图片格式数组。
.INPUTS
    无
.OUTPUTS
    string[]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-SupportedImageFormat
{
    [CmdletBinding()]
    param()

    return (Get-Configuration).App.SupportedImageFormats
}

<#
.SYNOPSIS
    检查文件是否为支持的图片格式
.DESCRIPTION
    判断给定文件对象的扩展名是否在支持的图片格式列表中。
    封装了重复的格式检查逻辑，提高代码复用性。
    支持管道输入，可以批量检查多个文件对象。
.PARAMETER File
    (object, Mandatory) 文件对象，需要包含 Extension 属性。
    支持 System.IO.FileInfo 和任何具有 Extension 属性的对象。
.PARAMETER SupportedFormats
    (string[], Optional) 支持的图片格式列表，若未指定则从配置读取。
.EXAMPLE
    Get-ChildItem -Path "C:\Images" -File | Test-SupportedImageFormat
    通过管道批量检查目录中所有文件是否为支持的图片格式。
.EXAMPLE
    Get-ChildItem -Path "C:\Images" -File | Where-Object { Test-SupportedImageFormat -File $PSItem }
    筛选出目录中所有支持的图片文件（非管道方式）。
.EXAMPLE
    Test-SupportedImageFormat -File $file -SupportedFormats @('.jpg', '.png')
    使用自定义格式列表检查文件。
.INPUTS
    object (通过管道输入文件对象)
.OUTPUTS
    bool (每个输入对象返回一个布尔值)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Test-SupportedImageFormat
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$File,
        [Parameter(Mandatory = $false)]
        [string[]]$SupportedFormats = $null
    )

    begin
    {
        # 只在调用者未提供 SupportedFormats 时从配置读取
        if (-not $SupportedFormats)
        {
            $SupportedFormats = Get-SupportedImageFormat
        }
    }

    process
    {
        # 检查输入对象是否包含 Extension 属性
        if (-not $File.PSObject.Properties['Extension'])
        {
            Write-WarningLog '输入对象缺少 Extension 属性'
            return $false
        }

        # 检查 Extension 值是否为 null 或空
        if (-not $File.Extension)
        {
            return $false
        }

        return $SupportedFormats -contains $File.Extension.ToLower()
    }
}

<#
.SYNOPSIS
    获取应用配置
.DESCRIPTION
    从配置实例获取应用配置对象。
.EXAMPLE
    Get-AppConfiguration
    获取应用配置对象。
.INPUTS
    无
.OUTPUTS
    ApplicationConfiguration
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-AppConfiguration
{
    [CmdletBinding()]
    param()

    return (Get-Configuration).App
}

<#
.SYNOPSIS
    获取路径配置
.DESCRIPTION
    从配置实例获取路径配置对象。
.EXAMPLE
    Get-PathConfiguration
    获取路径配置对象。
.INPUTS
    无
.OUTPUTS
    PathConfiguration
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-PathConfiguration
{
    [CmdletBinding()]
    param()

    return (Get-Configuration).Paths
}

Export-ModuleMember -Function @(
    'Get-NaturalSortKey',
    'Get-FfmpegPath',
    'Get-FfprobePath',
    'Get-RealCuganExePath',
    'Get-SupportedImageFormat',
    'Test-SupportedImageFormat',
    'Get-AppConfiguration',
    'Get-PathConfiguration'
)
