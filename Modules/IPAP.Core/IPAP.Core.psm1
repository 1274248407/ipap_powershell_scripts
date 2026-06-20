<#
.SYNOPSIS
    IPAP 工作流核心基础模块
.DESCRIPTION
    提供日志系统、配置解析和通用工具函数。
#>

# 项目根目录：使用模块自身路径向上两级（Modules/IPAP.Core -> 项目根目录）
# 使用 $MyInvocation.MyCommand.Definition 获取当前脚本路径，确保兼容性


$ProjectRoot = Join-Path $PSScriptRoot '..\..' | Resolve-Path | Select-Object -ExpandProperty Path

# 导入 PoShLog 模块
$PoShLogPath = Join-Path $ProjectRoot 'Modules\PoShLog'
if (Test-Path -LiteralPath $PoShLogPath)
{
    Import-Module -Name $PoShLogPath -Force -Scope Global
}

$Global:BinPath = Join-Path $ProjectRoot 'bin'
$Global:ConfigPath = Join-Path $ProjectRoot 'config.toml'
$Global:Settings = $null

# 支持的图片格式（从配置读取，fallback 到默认值）
$Global:SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')

$Global:DefaultSettings = @{
    paths        = @{
        base_project_dir   = ''
        project_dir_prefix = ''
    }
    app_settings = @{
        model_select        = 'models-se'
        max_workers         = 8
        upscale_timeout_sec = 600
    }
}




<#
.SYNOPSIS
    读取配置文件
.DESCRIPTION
    从指定路径读取 config.toml 配置文件，使用 PSToml 模块解析。
    若配置文件不存在、PSToml 不可用或解析失败，返回默认配置。
.PARAMETER ConfigPath
    (string) 配置文件路径，默认为脚本目录下的 config.toml。
    （适用于所有参数集）
.EXAMPLE
    Get-Config
    读取默认配置文件。
.EXAMPLE
    Get-Config -ConfigPath "C:\custom\config.toml"
    读取指定路径的配置文件。
.INPUTS
    无
.OUTPUTS
    hashtable
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-Config
{
    [CmdletBinding()]
    param (
        [string]$ConfigPath = $Global:ConfigPath
    )

    Write-InfoLog "正在读取配置文件: $ConfigPath"

    $DefaultSettings = @{
        paths        = @{
            base_project_dir   = ''
            project_dir_prefix = ''
        }
        app_settings = @{
            model_select        = 'models-se'
            max_workers         = 8
            upscale_timeout_sec = 600
        }
    }

    if (-not (Test-Path -LiteralPath $ConfigPath))
    {
        Write-WarningLog '配置文件不存在，使用默认设置'
        return $DefaultSettings
    }

    # 尝试使用 PSToml 解析
    $pstomlAvailable = $false
    try
    {
        $pstomlModulePath = Join-Path $Global:ProjectRoot 'Modules\PSToml'
        if (Test-Path -LiteralPath $pstomlModulePath)
        {
            Import-Module -Name $pstomlModulePath -Force -Scope Global -ErrorAction Stop
            $pstomlAvailable = $true
        }
    }
    catch
    {
        Write-WarningLog 'PSToml 模块加载失败'
    }

    if ($pstomlAvailable)
    {
        try
        {
            $config = Import-TomlFile -Path $ConfigPath
            Write-InfoLog '配置文件解析成功'
            return $config
        }
        catch
        {
            Write-WarningLog "配置文件解析失败: $($PSItem.Exception.Message)，使用默认设置"
            return $DefaultSettings
        }
    }
    else
    {
        Write-WarningLog 'PSToml 模块不可用，无法解析配置文件，使用默认设置'
        return $DefaultSettings
    }
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

    # 将连续的数字替换为前导零填充的格式，以便自然排序
    return ($InputString -replace '\d+', { $PSItem.Matches.Value.PadLeft(10, '0') })
}

<#
.SYNOPSIS
    获取 FFmpeg 可执行文件路径
.DESCRIPTION
    从配置文件读取 FFmpeg 路径，若配置路径不存在则回退到 PATH 环境变量。
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

    # 1. 优先从配置路径查找
    if ($Global:Settings -and $Global:Settings.paths -and $Global:Settings.paths.ffmpeg_exe)
    {
        $ConfiguredPath = Join-Path $ProjectRoot $Global:Settings.paths.ffmpeg_exe
        if (Test-Path -LiteralPath $ConfiguredPath)
        {
            return $ConfiguredPath
        }
    }

    # 2. 回退到 PATH 环境变量
    $ffmpegCommand = Get-Command 'ffmpeg' -ErrorAction SilentlyContinue
    if ($ffmpegCommand)
    {
        Write-InfoLog "FFmpeg 未在配置路径找到，回退到系统 PATH: $($ffmpegCommand.Source)"
        return $ffmpegCommand.Source
    }

    Write-ErrorLog '未找到 FFmpeg'
    return $null
}

<#
.SYNOPSIS
    获取 FFprobe 可执行文件路径
.DESCRIPTION
    从配置文件读取 FFprobe 路径，若配置路径不存在则回退到 PATH 环境变量。
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

    # 1. 优先从配置路径查找
    if ($Global:Settings -and $Global:Settings.paths -and $Global:Settings.paths.ffprobe_exe)
    {
        $ConfiguredPath = Join-Path $ProjectRoot $Global:Settings.paths.ffprobe_exe
        if (Test-Path -LiteralPath $ConfiguredPath)
        {
            return $ConfiguredPath
        }
    }

    # 2. 回退到 PATH 环境变量
    $ffprobeCommand = Get-Command 'ffprobe' -ErrorAction SilentlyContinue
    if ($ffprobeCommand)
    {
        Write-InfoLog "FFprobe 未在配置路径找到，回退到系统 PATH: $($ffprobeCommand.Source)"
        return $ffprobeCommand.Source
    }

    Write-ErrorLog '未找到 FFprobe'
    return $null
}

<#
.SYNOPSIS
    获取 Real-CUGAN 可执行文件路径
.DESCRIPTION
    从配置文件读取 Real-CUGAN 路径，若配置路径不存在则递归搜索 bin 目录。
.PARAMETER SearchPath
    (string) 搜索目录路径，默认为全局变量 BinPath。
    （适用于所有参数集）
.EXAMPLE
    Get-RealCuganExePath
    在默认路径查找 realcugan-ncnn-vulkan.exe。
.EXAMPLE
    Get-RealCuganExePath -SearchPath "C:\tools"
    在指定路径查找 realcugan-ncnn-vulkan.exe。
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
    param (
        [string]$SearchPath = $Global:BinPath
    )

    Write-InfoLog '正在搜索 realcugan-ncnn-vulkan.exe...'

    if (-not $SearchPath)
    {
        Write-ErrorLog '搜索路径为空'
        return $null
    }

    # 1. 优先从配置路径查找
    if ($Global:Settings -and $Global:Settings.paths -and $Global:Settings.paths.realcugan_exe)
    {
        $ConfiguredPath = Join-Path $ProjectRoot $Global:Settings.paths.realcugan_exe
        if (Test-Path -LiteralPath $ConfiguredPath)
        {
            Write-InfoLog "在配置路径找到 Real-CUGAN: $ConfiguredPath"
            return $ConfiguredPath
        }
    }

    # 2. 递归搜索兜底
    $exePath = Get-ChildItem -LiteralPath $SearchPath -Name 'realcugan-ncnn-vulkan.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($exePath)
    {
        $fullPath = Join-Path $SearchPath $exePath
        Write-InfoLog "Real-CUGAN 未在配置路径找到，通过递归搜索发现: $fullPath"
        return $fullPath
    }
    else
    {
        Write-ErrorLog '未找到 realcugan-ncnn-vulkan.exe'
        return $null
    }
}

<#
.SYNOPSIS
    初始化运行环境
.DESCRIPTION
    定位 realcugan-ncnn-vulkan.exe 并加载配置文件，将结果存储到全局变量中供后续操作使用。
    若无法定位可执行文件则记录警告日志。
.EXAMPLE
    Initialize-Environment
    初始化 IPAP 运行环境。
.INPUTS
    无
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Initialize-Environment
{
    [CmdletBinding()]
    param()

    Write-InfoLog '正在初始化运行环境...'

    # 1. 先加载配置
    $Global:Settings = Get-Config

    # 2. 从配置初始化 SupportedImageFormats
    if ($Global:Settings.app_settings.supported_image_formats)
    {
        $Global:SupportedImageFormats = $Global:Settings.app_settings.supported_image_formats
        Write-InfoLog "已从配置加载支持的图片格式: $($Global:SupportedImageFormats -join ', ')"
    }

    # 3. 初始化 Real-CUGAN 路径
    $Global:RealCuganExePath = Get-RealCuganExePath
    if (-not $Global:RealCuganExePath)
    {
        Write-WarningLog '无法定位 realcugan-ncnn-vulkan.exe，高清化功能将不可用'
    }

    Write-InfoLog '运行环境初始化完成'
}

Export-ModuleMember -Variable @(
    'BinPath',
    'ConfigPath',
    'Settings',
    'SupportedImageFormats',
    'DefaultSettings',
    'RealCuganExePath'
)

Export-ModuleMember -Function @(
    'Get-Config',
    'Get-NaturalSortKey',
    'Get-FfmpegPath',
    'Get-FfprobePath',
    'Get-RealCuganExePath',
    'Initialize-Environment'
)
<#
.SYNOPSIS
    IPAP 工作流核心基础模块
.DESCRIPTION
    提供日志系统、配置解析和通用工具函数。
#>

# 项目根目录：使用模块自身路径向上两级（Modules/IPAP.Core -> 项目根目录）
# 使用 $MyInvocation.MyCommand.Definition 获取当前脚本路径，确保兼容性


$ProjectRoot = Join-Path $PSScriptRoot '..\..' | Resolve-Path | Select-Object -ExpandProperty Path

# 导入 PoShLog 模块
$PoShLogPath = Join-Path $ProjectRoot 'Modules\PoShLog'
if (Test-Path -LiteralPath $PoShLogPath)
{
    Import-Module -Name $PoShLogPath -Force -Scope Global
}

$Global:BinPath = Join-Path $ProjectRoot 'bin'
$Global:ConfigPath = Join-Path $ProjectRoot 'config.toml'
$Global:Settings = $null

$Global:SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')

$Global:DefaultSettings = @{
    paths        = @{
        base_project_dir   = ''
        project_dir_prefix = ''
    }
    app_settings = @{
        model_select        = 'models-se'
        max_workers         = 8
        upscale_timeout_sec = 600
    }
}




<#
.SYNOPSIS
    读取配置文件
.DESCRIPTION
    从指定路径读取 config.toml 配置文件，使用 PSToml 模块解析。
    若配置文件不存在、PSToml 不可用或解析失败，返回默认配置。
.PARAMETER ConfigPath
    (string) 配置文件路径，默认为脚本目录下的 config.toml。
    （适用于所有参数集）
.EXAMPLE
    Get-Config
    读取默认配置文件。
.EXAMPLE
    Get-Config -ConfigPath "C:\custom\config.toml"
    读取指定路径的配置文件。
.INPUTS
    无
.OUTPUTS
    hashtable
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Get-Config
{
    [CmdletBinding()]
    param (
        [string]$ConfigPath = $Global:ConfigPath
    )

    Write-InfoLog "Reading configuration file: $ConfigPath"

    $DefaultSettings = @{
        paths        = @{
            base_project_dir   = ''
            project_dir_prefix = ''
        }
        app_settings = @{
            model_select        = 'models-se'
            max_workers         = 8
            upscale_timeout_sec = 600
        }
    }

    if (-not (Test-Path -LiteralPath $ConfigPath))
    {
        Write-WarningLog 'Configuration file not found, using default settings'
        return $DefaultSettings
    }

    # 尝试使用 PSToml 解析
    $pstomlAvailable = $false
    try
    {
        $pstomlModulePath = Join-Path $Global:ProjectRoot 'Modules\PSToml'
        if (Test-Path -LiteralPath $pstomlModulePath)
        {
            Import-Module -Name $pstomlModulePath -Force -Scope Global -ErrorAction Stop
            $pstomlAvailable = $true
            Write-InfoLog 'PSToml module imported successfully'
        }
    }
    catch
    {
        Write-WarningLog "Failed to import PSToml module: $($PSItem.Exception.Message)"
    }

    try
    {
        $config = $null
        
        if ($pstomlAvailable)
        {
            # 使用 PSToml 解析
            Write-InfoLog 'Using PSToml to parse configuration'
            $tomlContent = Get-Content -LiteralPath $ConfigPath -Raw
            $config = ConvertFrom-Toml -InputObject $tomlContent
        }
        else
        {
            Write-WarningLog 'PSToml module not available, using default settings'
            return $DefaultSettings
        }

        $configHash = @{}
        $configHash.paths = @{
            base_project_dir   = $config.paths.base_project_dir
            project_dir_prefix = $config.paths.project_dir_prefix
        }
        $configHash.app_settings = @{
            model_select        = $config.app_settings.model_select
            max_workers         = $config.app_settings.max_workers
            upscale_timeout_sec = $config.app_settings.upscale_timeout_sec
        }

        Write-InfoLog 'Configuration file parsed successfully'
        return $configHash
    }
    catch
    {
        Write-ErrorLog "Configuration file parsing failed: $($PSItem.Exception.Message), using default settings"
        return $DefaultSettings
    }
}

<#
.SYNOPSIS
    生成自然排序键
.DESCRIPTION
    将字符串按数字和非数字部分分割，生成可用于自然排序的数组。数字部分转换为整数，非数字部分保持原样。
.PARAMETER String
    (string, Mandatory) 需要生成排序键的输入字符串。
    （适用于所有参数集）
.EXAMPLE
    Get-NaturalSortKey -String "file12.txt"
    返回 @("file", 12, ".txt")。
.EXAMPLE
    Get-NaturalSortKey -String "Chapter 3.2"
    返回 @("Chapter ", 3, ".", 2)。
.INPUTS
    string
.OUTPUTS
    array
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Get-NaturalSortKey
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$String
    )

    $parts = [regex]::Split($String, '([0-9]+)')
    $result = @()

    foreach ($part in $parts)
    {
        if ($part -match '^[0-9]+$')
        {
            $result += [int]$part
        }
        elseif ($part)
        {
            $result += $part
        }
    }

    return $result
}

<#
.SYNOPSIS
    查找 realcugan-ncnn-vulkan.exe 可执行文件路径
.DESCRIPTION
    在指定搜索路径中递归查找 realcugan-ncnn-vulkan.exe 文件，返回完整路径或 $null。
    若未找到文件则记录错误日志。
.PARAMETER SearchPath
    (string) 搜索目录路径，默认为全局变量 BinPath。
    （适用于所有参数集）
.EXAMPLE
    Get-RealCuganExePath
    在默认路径查找 realcugan-ncnn-vulkan.exe。
.EXAMPLE
    Get-RealCuganExePath -SearchPath "C:\tools"
    在指定路径查找 realcugan-ncnn-vulkan.exe。
.INPUTS
    无
.OUTPUTS
    string 或 $null
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Get-RealCuganExePath
{
    [CmdletBinding()]
    param (
        [string]$SearchPath = $Global:BinPath
    )

    Write-InfoLog 'Searching for realcugan-ncnn-vulkan.exe...'

    if (-not $SearchPath)
    {
        Write-ErrorLog 'Search path is empty'
        return $null
    }

    $exePath = Get-ChildItem -LiteralPath $SearchPath -Name 'realcugan-ncnn-vulkan.exe' -Recurse -ErrorAction SilentlyContinue

    if ($exePath)
    {
        $fullPath = Join-Path $SearchPath $exePath
        Write-InfoLog "Found realcugan-ncnn-vulkan.exe: $fullPath"
        return $fullPath
    }
    else
    {
        Write-ErrorLog 'realcugan-ncnn-vulkan.exe not found'
        return $null
    }
}
<#
.SYNOPSIS
    初始化运行环境
.DESCRIPTION
    定位 realcugan-ncnn-vulkan.exe 并加载配置文件，将结果存储到全局变量中供后续操作使用。
    若无法定位可执行文件则记录警告日志。
.EXAMPLE
    Initialize-Environment
    初始化 IPAP 运行环境。
.INPUTS
    无
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Initialize-Environment
{
    [CmdletBinding()]
    param()

    Write-InfoLog 'Initializing environment...'

    $Global:RealCuganExePath = Get-RealCuganExePath
    if (-not $Global:RealCuganExePath)
    {
        Write-WarningLog 'Cannot locate realcugan-ncnn-vulkan.exe, upscaling functionality will be unavailable'
    }

    $Global:Settings = Get-Config

    Write-InfoLog 'Environment initialization completed'
}

Export-ModuleMember -Variable @(
    'BinPath',
    'ConfigPath',
    'Settings',
    'SupportedImageFormats',
    'DefaultSettings',
    'RealCuganExePath'
)

Export-ModuleMember -Function @(
    'Get-Config',
    'Get-NaturalSortKey',
    'Get-RealCuganExePath',
    'Initialize-Environment'
)
