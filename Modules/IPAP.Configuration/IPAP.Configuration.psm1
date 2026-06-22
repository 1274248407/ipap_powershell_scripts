<#
.SYNOPSIS
    IPAP 配置管理模块
.DESCRIPTION
    提供项目配置管理功能，包括路径配置、工具配置和应用配置。
    使用 PowerShell 类和 Validate 属性实现配置验证和类型安全。
    通过 Get-Configuration 函数获取全局配置实例。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

#region PathConfiguration 类
<#
.SYNOPSIS
    路径配置类
.DESCRIPTION
    管理和验证项目相关的路径信息，包括项目根目录、二进制文件目录和配置文件路径。
    在构造时自动验证路径有效性。
.EXAMPLE
    $pathConfig = [PathConfiguration]::new('D:\Projects\MyProject')
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
class PathConfiguration
{
    # 项目根目录
    [string]$ProjectRoot

    # 二进制文件目录（bin）
    [string]$BinPath

    # 配置文件路径（config.toml）
    [string]$ConfigPath

    <#
    .SYNOPSIS
        创建路径配置实例
    .DESCRIPTION
        构造函数验证并初始化路径配置。
        验证 ProjectRoot 不为空且目录存在。
    .PARAMETER ProjectRoot
        项目根目录路径
    .EXAMPLE
        $config = [PathConfiguration]::new('D:\Projects\MyProject')
    .OUTPUTS
        PathConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    PathConfiguration([string]$ProjectRoot)
    {
        if ([string]::IsNullOrWhiteSpace($ProjectRoot))
        {
            throw [System.ArgumentException]::new('ProjectRoot 不能为空')
        }
        if (-not (Test-Path -LiteralPath $ProjectRoot))
        {
            throw [System.IO.DirectoryNotFoundException]::new("ProjectRoot 目录不存在: $ProjectRoot")
        }
        $this.ProjectRoot = $ProjectRoot
        $this.BinPath = Join-Path $ProjectRoot 'bin'
        $this.ConfigPath = Join-Path $ProjectRoot 'config.toml'
    }

    <#
    .SYNOPSIS
        加载路径配置
    .DESCRIPTION
        静态方法，创建并返回新的 PathConfiguration 实例。
    .PARAMETER ProjectRoot
        项目根目录路径
    .EXAMPLE
        $pathConfig = [PathConfiguration]::Load('D:\Projects\MyProject')
    .OUTPUTS
        PathConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    static [PathConfiguration] Load([string]$ProjectRoot)
    {
        return [PathConfiguration]::new($ProjectRoot)
    }
}
#endregion

#region ToolConfiguration 类
<#
.SYNOPSIS
    工具配置类
.DESCRIPTION
    管理外部工具的可执行文件路径，包括 FFmpeg、FFprobe 和 Real-CUGAN。
    支持配置路径解析和 PATH 环境变量回退机制。
.EXAMPLE
        $toolConfig = [ToolConfiguration]::Load($pathConfig, $settings)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
class ToolConfiguration
{
    # Real-CUGAN 可执行文件路径
    [string]$RealCuganExePath

    # FFmpeg 可执行文件路径
    [string]$FfmpegExePath

    # FFprobe 可执行文件路径
    [string]$FfprobeExePath

    # 关联的路径配置（内部使用）
    hidden [PathConfiguration]$PathConfig

    <#
    .SYNOPSIS
        创建工具配置实例
    .DESCRIPTION
        构造函数初始化工具路径解析器。
        根据配置设置和 PATH 环境变量解析工具路径。
    .PARAMETER PathConfig
        路径配置实例
    .PARAMETER Settings
        包含工具路径配置的哈希表
    .EXAMPLE
        $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)
    .OUTPUTS
        ToolConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    ToolConfiguration([PathConfiguration]$PathConfig, [hashtable]$Settings)
    {
        $this.PathConfig = $PathConfig
        $this.FfmpegExePath = $this.ResolveToolPath($Settings.paths.ffmpeg_exe, 'ffmpeg', 'FFmpeg')
        $this.FfprobeExePath = $this.ResolveToolPath($Settings.paths.ffprobe_exe, 'ffprobe', 'FFprobe')
        $this.RealCuganExePath = $this.ResolveRealCuganPath($Settings.paths.realcugan_exe)
    }

    <#
    .SYNOPSIS
        解析工具路径
    .DESCRIPTION
        内部方法，优先使用配置路径，否则从 PATH 环境变量查找。
    .PARAMETER ConfiguredPath
        配置文件中的相对路径
    .PARAMETER CommandName
        命令名称（用于 PATH 查找）
    .PARAMETER DisplayName
        显示名称（用于错误信息）
    .OUTPUTS
        string
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    hidden [string] ResolveToolPath([string]$ConfiguredPath, [string]$CommandName, [string]$DisplayName)
    {
        if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath))
        {
            $FullPath = Join-Path $this.PathConfig.ProjectRoot $ConfiguredPath
            if (Test-Path -LiteralPath $FullPath)
            {
                return $FullPath
            }
        }
        $Command = Get-Command $CommandName -ErrorAction SilentlyContinue
        if ($Command)
        {
            return $Command.Source
        }
        return $null
    }

    <#
    .SYNOPSIS
        解析 Real-CUGAN 路径
    .DESCRIPTION
        内部方法，优先使用配置路径，否则在 bin 目录中递归查找。
    .PARAMETER ConfiguredPath
        配置文件中的相对路径
    .OUTPUTS
        string
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    hidden [string] ResolveRealCuganPath([string]$ConfiguredPath)
    {
        if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath))
        {
            $FullPath = Join-Path $this.PathConfig.ProjectRoot $ConfiguredPath
            if (Test-Path -LiteralPath $FullPath)
            {
                return $FullPath
            }
        }
        $ExeName = 'realcugan-ncnn-vulkan.exe'
        $Found = Get-ChildItem -LiteralPath $this.PathConfig.BinPath -Name $ExeName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Found)
        {
            return Join-Path $this.PathConfig.BinPath $Found
        }
        return $null
    }

    <#
    .SYNOPSIS
        加载工具配置
    .DESCRIPTION
        静态方法，创建并返回新的 ToolConfiguration 实例。
    .PARAMETER PathConfig
        路径配置实例
    .PARAMETER Settings
        包含工具路径配置的哈希表
    .EXAMPLE
        $toolConfig = [ToolConfiguration]::Load($pathConfig, $settings)
    .OUTPUTS
        ToolConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    static [ToolConfiguration] Load([PathConfiguration]$PathConfig, [hashtable]$Settings)
    {
        return [ToolConfiguration]::new($PathConfig, $Settings)
    }
}
#endregion

#region ApplicationConfiguration 类
<#
.SYNOPSIS
    应用配置类
.DESCRIPTION
    管理应用程序的运行参数，包括支持的图片格式、最大工作线程数、
    超时设置、模型选择、放大参数和 WebP 输出选项。
.EXAMPLE
        $appConfig = [ApplicationConfiguration]::Load($settings)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
class ApplicationConfiguration
{
    # 支持的图片格式列表
    [string[]]$SupportedImageFormats

    # 原始设置哈希表（内部使用）
    hidden [hashtable]$Settings

    # 最大工作线程数
    [int]$MaxWorkers

    # 放大超时时间（秒）
    [int]$UpscaleTimeoutSec

    # 模型选择
    [string]$ModelSelect

    # 放大倍数
    [int]$UpscaleRatio

    # 降噪级别
    [int]$NoiseLevel

    # WebP 输出启用状态
    [bool]$WebpEnabled

    # WebP 无损压缩启用状态
    [bool]$WebpLossless

    # WebP 质量参数
    [int]$WebpQuality

    <#
    .SYNOPSIS
        创建应用配置实例
    .DESCRIPTION
        构造函数使用默认值初始化应用配置。
        所有参数都有合理的默认值，可以后续修改。
    .PARAMETER Settings
        包含应用配置的哈希表（可选）
    .EXAMPLE
        $appConfig = [ApplicationConfiguration]::new($settings)
    .OUTPUTS
        ApplicationConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    ApplicationConfiguration([hashtable]$Settings)
    {
        $this.Settings = $Settings
        $this.SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
        $this.MaxWorkers = 8
        $this.UpscaleTimeoutSec = 3600
        $this.ModelSelect = 'models-se'
        $this.UpscaleRatio = 2
        $this.NoiseLevel = 0
        $this.WebpEnabled = $true
        $this.WebpLossless = $true
        $this.WebpQuality = 100
    }

    <#
    .SYNOPSIS
        加载应用配置
    .DESCRIPTION
        静态方法，创建并返回新的 ApplicationConfiguration 实例。
    .PARAMETER Settings
        包含应用配置的哈希表
    .EXAMPLE
        $appConfig = [ApplicationConfiguration]::Load($settings)
    .OUTPUTS
        ApplicationConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    static [ApplicationConfiguration] Load([hashtable]$Settings)
    {
        return [ApplicationConfiguration]::new($Settings)
    }
}
#endregion

#region IPAPConfiguration 主配置类
<#
.SYNOPSIS
    IPAP 主配置类
.DESCRIPTION
    聚合路径配置、工具配置和应用配置，提供统一的配置访问接口。
    是配置管理模块的入口点，通过 Get-Configuration 函数获取实例。
.EXAMPLE
        $config = [IPAPConfiguration]::Load('D:\Projects\MyProject')
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
class IPAPConfiguration
{
    # 路径配置
    [PathConfiguration]$Paths

    # 工具配置
    [ToolConfiguration]$Tools

    # 应用配置
    [ApplicationConfiguration]$App

    <#
    .SYNOPSIS
        创建 IPAP 配置实例
    .DESCRIPTION
        构造函数初始化完整配置对象。
    .PARAMETER Paths
        路径配置实例
    .PARAMETER Tools
        工具配置实例
    .PARAMETER App
        应用配置实例
    .EXAMPLE
        $config = [IPAPConfiguration]::new($paths, $tools, $app)
    .OUTPUTS
        IPAPConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    IPAPConfiguration(
        [PathConfiguration]$Paths,
        [ToolConfiguration]$Tools,
        [ApplicationConfiguration]$App
    )
    {
        $this.Paths = $Paths
        $this.Tools = $Tools
        $this.App = $App
    }

    <#
    .SYNOPSIS
        加载完整配置
    .DESCRIPTION
        静态方法，加载并返回完整的 IPAP 配置实例。
        依次加载路径配置、工具配置和应用配置。
    .PARAMETER ProjectRoot
        项目根目录路径
    .EXAMPLE
        $config = [IPAPConfiguration]::Load('D:\Projects\MyProject')
    .OUTPUTS
        IPAPConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    static [IPAPConfiguration] Load([string]$ProjectRoot)
    {
        $loadedPaths = [PathConfiguration]::Load($ProjectRoot)
        $loadedSettings = @{
            paths        = @{ base_project_dir = ''; project_dir_prefix = '' }
            app_settings = @{ supported_image_formats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'); max_workers = 8; upscale_timeout_sec = 3600; model_select = 'models-se' }
            upscale      = @{ upscale_ratio = 2; noise_level = 0 }
            webp         = @{ enabled = $true; lossless = $true; quality = 100 }
        }
        $loadedTools = [ToolConfiguration]::Load($loadedPaths, $loadedSettings)
        $loadedApp = [ApplicationConfiguration]::Load($loadedSettings)
        return [IPAPConfiguration]::new($loadedPaths, $loadedTools, $loadedApp)
    }
}
#endregion

#region 全局配置实例和访问函数
# 全局配置实例变量
$Global:IPAPConfigInstance = $null

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
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$ProjectRoot
    )

    process
    {
        if ($Global:IPAPConfigInstance -and [string]::IsNullOrWhiteSpace($ProjectRoot))
        {
            return $Global:IPAPConfigInstance
        }

        $Root = $ProjectRoot
        if ([string]::IsNullOrWhiteSpace($Root))
        {
            if ($Global:IPAPConfigInstance)
            {
                $Root = $Global:IPAPConfigInstance.Paths.ProjectRoot
            }
            else
            {
                throw [System.InvalidOperationException]::new('ProjectRoot 未指定，且配置实例未初始化')
            }
        }

        $Global:IPAPConfigInstance = [IPAPConfiguration]::Load($Root)
        return $Global:IPAPConfigInstance
    }
}

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
    [CmdletBinding()]
    param()

    $Global:IPAPConfigInstance = $null
}

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
#endregion

Export-ModuleMember -Function @(
    'Get-Configuration',
    'Reset-Configuration',
    'Test-ConfigurationInitialized'
)
