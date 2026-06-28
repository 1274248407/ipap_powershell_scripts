[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
param()

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
    管理和验证项目相关的路径信息，包括项目根目录、二进制文件目录、配置文件路径和源图片目录。
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

    # 漫画/翻译项目工作区的基准目录
    [string]$BaseProjectDir

    # 二进制文件目录（bin）
    [string]$BinPath

    # 配置文件路径（config.toml）
    [string]$ConfigPath

    # 源图片目录（待处理的漫画图片所在目录）
    [string]$SourceDir

    <#
    .SYNOPSIS
        创建路径配置实例
    .DESCRIPTION
        构造函数验证并初始化路径配置。
        验证 ProjectRoot 不为空且目录存在。
    .PARAMETER ProjectRoot
        项目根目录路径
    .PARAMETER SourceDir
        源图片目录路径（可选）
    .EXAMPLE
        $config = [PathConfiguration]::new('D:\Projects\MyProject')
    .OUTPUTS
        PathConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    PathConfiguration([string]$ProjectRoot, [string]$BaseProjectDir = $null, [string]$SourceDir = $null)
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
        $this.BaseProjectDir = $BaseProjectDir
        $this.BinPath = Join-Path $ProjectRoot 'bin'
        $this.ConfigPath = Join-Path $ProjectRoot 'config.toml'
        $this.SourceDir = $SourceDir
    }

    <#
    .SYNOPSIS
        加载路径配置
    .DESCRIPTION
        静态方法，创建并返回新的 PathConfiguration 实例。
    .PARAMETER ProjectRoot
        项目根目录路径
    .PARAMETER SourceDir
        源图片目录路径（可选）
    .EXAMPLE
        $pathConfig = [PathConfiguration]::Load('D:\Projects\MyProject')
    .OUTPUTS
        PathConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    static [PathConfiguration] Load([string]$ProjectRoot, [string]$BaseProjectDir = $null, [string]$SourceDir = $null)
    {
        return [PathConfiguration]::new($ProjectRoot, $BaseProjectDir, $SourceDir)
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

#region ProjectConfiguration 类
<#
.SYNOPSIS
    项目配置类
.DESCRIPTION
    管理项目的元数据信息，包括作者、原作品名、中文译名和简介等。
    这些信息用于生成项目目录名和 README 文件。
.EXAMPLE
    $projectConfig = [ProjectConfiguration]::new($settings)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
class ProjectConfiguration
{
    # 作者名
    [string]$Author

    # 原作品名（原文）
    [string]$OriginalTitle

    # 作品中文译名
    [string]$ChineseTitle

    # 原文简介
    [string]$OriginalOverview

    # 中文简介
    [string]$ChineseOverview

    <#
    .SYNOPSIS
        创建项目配置实例
    .DESCRIPTION
        构造函数使用配置设置初始化项目元数据。
        如果配置中没有提供值，则使用空字符串作为默认值。
    .PARAMETER Settings
        包含项目配置的哈希表
    .EXAMPLE
        $projectConfig = [ProjectConfiguration]::new($settings)
    .OUTPUTS
        ProjectConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    ProjectConfiguration([hashtable]$Settings)
    {
        # 先初始化所有属性为空字符串
        $this.Author = ''
        $this.OriginalTitle = ''
        $this.ChineseTitle = ''
        $this.OriginalOverview = ''
        $this.ChineseOverview = ''

        # 然后从配置读取值
        if ($Settings -and $Settings.ContainsKey('project'))
        {
            $projectSettings = $Settings.project
            if ($projectSettings.ContainsKey('author')) { $this.Author = $projectSettings.author }
            if ($projectSettings.ContainsKey('original_title')) { $this.OriginalTitle = $projectSettings.original_title }
            if ($projectSettings.ContainsKey('chinese_title')) { $this.ChineseTitle = $projectSettings.chinese_title }
            if ($projectSettings.ContainsKey('original_overview')) { $this.OriginalOverview = $projectSettings.original_overview }
            if ($projectSettings.ContainsKey('chinese_overview')) { $this.ChineseOverview = $projectSettings.chinese_overview }
        }
    }

    <#
    .SYNOPSIS
        生成项目名称
    .DESCRIPTION
        根据作者和原作品名生成项目名称，格式为 [作者] 原作品名。
    .OUTPUTS
        string
    .EXAMPLE
        $projectName = $projectConfig.GetProjectName()
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    [string] GetProjectName()
    {
        if (-not [string]::IsNullOrWhiteSpace($this.Author) -and -not [string]::IsNullOrWhiteSpace($this.OriginalTitle))
        {
            $result = '[{0}] {1}' -f $this.Author, $this.OriginalTitle
            return $result
        }
        return $this.OriginalTitle
    }

    <#
    .SYNOPSIS
        加载项目配置
    .DESCRIPTION
        静态方法，创建并返回新的 ProjectConfiguration 实例。
    .PARAMETER Settings
        包含项目配置的哈希表
    .EXAMPLE
        $projectConfig = [ProjectConfiguration]::Load($settings)
    .OUTPUTS
        ProjectConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    static [ProjectConfiguration] Load([hashtable]$Settings)
    {
        return [ProjectConfiguration]::new($Settings)
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
        构造函数从配置哈希表读取值初始化应用配置。
        如果配置中没有提供值，则使用合理的默认值。
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

        # 从配置读取值，使用默认值作为回退
        if ($Settings.ContainsKey('app_settings'))
        {
            $appSettings = $Settings.app_settings
            $this.SupportedImageFormats = if ($appSettings.ContainsKey('supported_image_formats') -and $appSettings.supported_image_formats) { $appSettings.supported_image_formats } else { @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp') }
            $this.MaxWorkers = if ($appSettings.ContainsKey('max_workers')) { [int]$appSettings.max_workers } else { 8 }
            $this.UpscaleTimeoutSec = if ($appSettings.ContainsKey('upscale_timeout_sec')) { [int]$appSettings.upscale_timeout_sec } else { 3600 }
            $this.ModelSelect = if ($appSettings.ContainsKey('model_select')) { $appSettings.model_select } else { 'models-se' }
        }
        else
        {
            $this.SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
            $this.MaxWorkers = 8
            $this.UpscaleTimeoutSec = 3600
            $this.ModelSelect = 'models-se'
        }

        if ($Settings.ContainsKey('upscale'))
        {
            $upscaleSettings = $Settings.upscale
            $this.UpscaleRatio = if ($upscaleSettings.ContainsKey('upscale_ratio')) { [int]$upscaleSettings.upscale_ratio } else { 2 }
            $this.NoiseLevel = if ($upscaleSettings.ContainsKey('noise_level')) { [int]$upscaleSettings.noise_level } else { 0 }
        }
        else
        {
            $this.UpscaleRatio = 2
            $this.NoiseLevel = 0
        }

        if ($Settings.ContainsKey('webp'))
        {
            $webpSettings = $Settings.webp
            $this.WebpEnabled = if ($webpSettings.ContainsKey('enabled')) { [bool]$webpSettings.enabled } else { $true }
            $this.WebpLossless = if ($webpSettings.ContainsKey('lossless')) { [bool]$webpSettings.lossless } else { $true }
            $this.WebpQuality = if ($webpSettings.ContainsKey('quality')) { [int]$webpSettings.quality } else { 100 }
        }
        else
        {
            $this.WebpEnabled = $true
            $this.WebpLossless = $true
            $this.WebpQuality = 100
        }
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

    # 项目配置
    [ProjectConfiguration]$Project

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
    .PARAMETER Project
        项目配置实例
    .EXAMPLE
        $config = [IPAPConfiguration]::new($paths, $tools, $app, $project)
    .OUTPUTS
        IPAPConfiguration
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    IPAPConfiguration(
        [PathConfiguration]$Paths,
        [ToolConfiguration]$Tools,
        [ApplicationConfiguration]$App,
        [ProjectConfiguration]$Project
    )
    {
        $this.Paths = $Paths
        $this.Tools = $Tools
        $this.App = $App
        $this.Project = $Project
    }

    <#
    .SYNOPSIS
        加载完整配置
    .DESCRIPTION
        静态方法，加载并返回完整的 IPAP 配置实例。
        依次加载路径配置、工具配置、应用配置和项目配置。
        首先尝试从 config.toml 文件读取配置，失败则使用默认值。
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
        $loadedSettings = [IPAPConfiguration]::ReadConfigFile($ProjectRoot)
        $baseProjectDir = if ($loadedSettings.ContainsKey('paths') -and $loadedSettings.paths.ContainsKey('base_project_dir')) { $loadedSettings.paths.base_project_dir } else { $null }
        $sourceDir = if ($loadedSettings.ContainsKey('paths') -and $loadedSettings.paths.ContainsKey('source_dir')) { $loadedSettings.paths.source_dir } else { $null }
        $loadedPaths = [PathConfiguration]::Load($ProjectRoot, $baseProjectDir, $sourceDir)
        $loadedTools = [ToolConfiguration]::Load($loadedPaths, $loadedSettings)
        $loadedApp = [ApplicationConfiguration]::Load($loadedSettings)
        $loadedProject = [ProjectConfiguration]::Load($loadedSettings)
        return [IPAPConfiguration]::new($loadedPaths, $loadedTools, $loadedApp, $loadedProject)
    }

    <#
    .SYNOPSIS
        读取 TOML 配置文件
    .DESCRIPTION
        内部方法，尝试从 config.toml 文件读取配置。
        如果文件不存在或解析失败，返回默认配置。
    .PARAMETER ProjectRoot
        项目根目录路径
    .OUTPUTS
        hashtable
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    hidden static [hashtable] ReadConfigFile([string]$ProjectRoot)
    {
        $configPath = Join-Path $ProjectRoot 'config.toml'
        $defaultSettings = @{
            paths        = @{ base_project_dir = ''; project_dir_prefix = ''; archive_dir = ''; source_dir = ''; ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' }
            project      = @{ author = ''; original_title = ''; chinese_title = ''; original_overview = ''; chinese_overview = '' }
            app_settings = @{ supported_image_formats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'); max_workers = 8; upscale_timeout_sec = 3600; model_select = 'models-se' }
            upscale      = @{ upscale_ratio = 2; noise_level = 0 }
            webp         = @{ enabled = $true; lossless = $true; quality = 100 }
        }

        if (-not (Test-Path -LiteralPath $configPath))
        {
            Write-Verbose "配置文件不存在: $configPath，使用默认配置"
            return $defaultSettings
        }

        try
        {
            $PSTomlPath = Join-Path $ProjectRoot 'Modules\PSToml'
            if (Test-Path -LiteralPath $PSTomlPath)
            {
                Import-Module $PSTomlPath -Force -Scope Local
            }

            if (Get-Command 'ConvertFrom-Toml' -ErrorAction SilentlyContinue)
            {
                $content = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
                $parsedSettings = $null
                $parseError = $null
                try
                {
                    $parsedSettings = ConvertFrom-Toml -InputObject $content -ErrorAction Stop
                }
                catch
                {
                    $parseError = $PSItem
                }

                # 如果解析失败且错误与字符串转义有关，尝试自动修复 Windows 路径转义
                if (-not $parsedSettings -and $parseError -and $parseError.Exception.Message -match 'Unexpected escape character')
                {
                    Write-Warning 'TOML 解析失败，检测到可能是 Windows 路径反斜杠转义问题，正在尝试自动修复...'
                    try
                    {
                        # 将双引号字符串中的单个反斜杠替换为双反斜杠（排除已正确转义的 \\\\、\\"、\\n 等）
                        # 自动修复双引号字符串中的 Windows 路径反斜杠：
                        # 1) 临时保护已正确转义的序列（\\、\"、\n、\t 等）
                        # 2) 将剩余的单个反斜杠替换为双反斜杠
                        # 3) 恢复被保护的合法转义序列
                        $protectedContent = $content
                        $escapeMap = @{
                            '\\'  = "`u{E0000}"
                            '\"'  = "`u{E0001}"
                            '\\n' = "`u{E0002}"
                            '\\t' = "`u{E0003}"
                            '\\r' = "`u{E0004}"
                            '\\b' = "`u{E0005}"
                            '\\f' = "`u{E0006}"
                        }
                        foreach ($escape in $escapeMap.Keys)
                        {
                            $protectedContent = $protectedContent.Replace($escape, $escapeMap[$escape])
                        }

                        $fixedContent = $protectedContent.Replace('\', '\\')
                        foreach ($escape in $escapeMap.Keys)
                        {
                            $fixedContent = $fixedContent.Replace($escapeMap[$escape], $escape)
                        }
                        $parsedSettings = ConvertFrom-Toml -InputObject $fixedContent -ErrorAction Stop
                        Write-Warning "自动修复成功。建议将 config.toml 中的 Windows 路径改为单引号字面量字符串，例如 source_dir = 'C:\\path\\to\\dir'"
                    }
                    catch
                    {
                        throw [System.InvalidOperationException]::new("无法解析 config.toml: $($parseError.Exception.Message)。常见原因：Windows 路径使用了双引号但未正确转义反斜杠。请将路径改为单引号字面量字符串，例如 source_dir = 'C:\\path\\to\\dir'")
                    }
                }
                elseif ($parseError)
                {
                    throw [System.InvalidOperationException]::new("无法解析 config.toml: $($parseError.Exception.Message)")
                }

                $parsedHashtable = [hashtable]$parsedSettings
                #  为什么转换？ ConvertFrom-Toml 解析出来的子配置块默认是 OrderedDictionary（记住了顺序，但查找慢且不可修改），
                # 而本项目的其他代码（如 MergeSettings）习惯用 Hashtable（不记顺序，但查找极快且可随意修改）。
                # 循环在干嘛？ 遍历配置的每一个顶级分类（如 paths、project），如果发现它还是个有序字典，
                # 就把它“脱壳”换成哈希表，确保数据格式统一。
                # 注意：必须先复制 Keys 再循环，避免在枚举过程中修改集合。
                $topLevelKeys = @($parsedHashtable.Keys)
                foreach ($key in $topLevelKeys)
                {
                    if ($parsedHashtable[$key] -is [System.Collections.Specialized.OrderedDictionary])
                    {
                        $parsedHashtable[$key] = [hashtable]$parsedHashtable[$key]
                    }
                }
                return [IPAPConfiguration]::MergeSettings($parsedHashtable, $defaultSettings)
            }
            else
            {
                Write-Verbose 'PSToml 模块未找到，使用默认配置'
                return $defaultSettings
            }
        }
        catch
        {
            throw $PSItem
        }
    }

    <#
    .SYNOPSIS
        合并配置设置
    .DESCRIPTION
        内部方法，将解析的配置与默认配置合并，确保所有必要的键都存在。
    .PARAMETER ParsedSettings
        从 TOML 文件解析的配置
    .PARAMETER DefaultSettings
        默认配置
    .OUTPUTS
        hashtable
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    hidden static [hashtable] MergeSettings([hashtable]$ParsedSettings, [hashtable]$DefaultSettings)
    {
        $merged = $DefaultSettings.Clone()

        # 如果用户配置和默认配置都有这个分类（比如 paths），且它们里面都嵌套着小配置项（哈希表），就进入第二层循环，逐个对比小项。
        # 这叫浅合并。比如默认配置里 paths 有 A、B、C 三个路径，用户只配了 A。这段代码会只把 A 替换成用户的，保留默认的 B 和 C。
        foreach ($key in $ParsedSettings.Keys)
        {
            if ($merged.ContainsKey($key))
            {
                if ($merged[$key] -is [hashtable] -and $ParsedSettings[$key] -is [hashtable])
                {
                    $parsedSubTable = [hashtable]$ParsedSettings[$key]
                    foreach ($subKey in $parsedSubTable.Keys)
                    {
                        if ($merged[$key].ContainsKey($subKey))
                        {
                            $merged[$key][$subKey] = $parsedSubTable[$subKey]
                        }
                    }
                }
                # 如果当前键在默认配置里存在，但它不是嵌套的哈希表（比如只是一个数字或字符串），直接用用户的值覆盖默认值
                else
                {
                    $merged[$key] = $ParsedSettings[$key]
                }
            }
            # 如果用户写了一个默认配置里根本没有的键，直接把它加进合并表
            else
            {
                $merged[$key] = $ParsedSettings[$key]
            }
        }

        return $merged
    }
}
#endregion

#region 全局配置实例和访问函数
# 全局配置实例变量 - 作为单例存储配置，供所有模块访问
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('全局配置实例', '重置'))
    {
        $Global:IPAPConfigInstance = $null
    }
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

<#
.SYNOPSIS
    确认项目配置
.DESCRIPTION
    显示当前配置信息，询问用户是否应用配置。如果用户选择不应用，提供两种方式修改配置：使用文本编辑器或控制台直接输入。
.PARAMETER Config
    IPAPConfiguration 实例（可选），如果未指定则使用全局配置实例。
.EXAMPLE
    # 显示配置并获取用户确认后的配置
    $config = Confirm-ProjectConfiguration
.INPUTS
    IPAPConfiguration
.OUTPUTS
    IPAPConfiguration
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Confirm-ProjectConfiguration
{
    [CmdletBinding()]
    [OutputType([IPAPConfiguration])]
    param(
        [IPAPConfiguration]$Config = $null
    )

    if (-not $Config)
    {
        $Config = Get-Configuration
    }

    Write-InfoLog '--- 当前配置信息预览 ---'

    Write-WarningLog '【路径配置】'
    Write-InfoLog "  项目根目录: $($Config.Paths.ProjectRoot)"
    Write-InfoLog "  基准项目目录: $(if ($Config.Paths.BaseProjectDir) { $Config.Paths.BaseProjectDir } else { '[未配置]' })"
    Write-InfoLog "  源图片目录: $(if ($Config.Paths.SourceDir) { $Config.Paths.SourceDir } else { '[未配置]' })"

    Write-WarningLog '【项目信息】'
    Write-InfoLog "  作者: $(if ($Config.Project.Author) { $Config.Project.Author } else { '[未配置]' })"
    Write-InfoLog "  原作品名: $(if ($Config.Project.OriginalTitle) { $Config.Project.OriginalTitle } else { '[未配置]' })"
    Write-InfoLog "  中文译名: $(if ($Config.Project.ChineseTitle) { $Config.Project.ChineseTitle } else { '[未配置]' })"
    Write-InfoLog "  原文简介: $(if ($Config.Project.OriginalOverview) { '已配置' } else { '[未配置]' })"
    Write-InfoLog "  中文简介: $(if ($Config.Project.ChineseOverview) { '已配置' } else { '[未配置]' })"

    Write-WarningLog '【应用配置】'
    Write-InfoLog "  最大工作线程数: $($Config.App.MaxWorkers)"
    Write-InfoLog "  放大倍数: $($Config.App.UpscaleRatio)"
    Write-InfoLog "  模型选择: $($Config.App.ModelSelect)"

    do
    {
        $response = Read-Host '是否应用当前配置？(Y/N)'
    } while ($response -ne 'Y' -and $response -ne 'y' -and $response -ne 'N' -and $response -ne 'n')

    if ($response -eq 'Y' -or $response -eq 'y')
    {
        Write-InfoLog '应用当前配置'
        return $Config
    }

    Write-WarningLog '您选择不应用当前配置，请选择修改方式：'
    Write-InfoLog '  1) 使用文本编辑器修改 config.toml（推荐）'
    Write-InfoLog '  2) 在控制台直接输入'

    do
    {
        $choice = Read-Host '请选择 (1/2)'
    } while ($choice -ne '1' -and $choice -ne '2')

    if ($choice -eq '1')
    {
        Write-InfoLog '正在打开配置文件...'
        try
        {
            Start-Process -FilePath $Config.Paths.ConfigPath
            Write-InfoLog '配置文件已打开，请修改后保存。'
            $null = Read-Host '按 Enter 键继续...'
        }
        catch
        {
            Write-ErrorLog "无法自动打开配置文件，请手动打开: $($Config.Paths.ConfigPath)"
            $null = Read-Host '按 Enter 键继续...'
        }

        # 重置前保存 ProjectRoot，避免重置后无法恢复
        $projectRoot = $Config.Paths.ProjectRoot
        Reset-Configuration
        $Config = Get-Configuration -ProjectRoot $projectRoot
        return Confirm-ProjectConfiguration -Config $Config
    }
    else
    {
        Write-WarningLog '请在控制台输入配置信息：'

        Write-WarningLog '【路径配置】'
        $newSourceDir = Read-Host "源图片目录 [当前: $($Config.Paths.SourceDir)]"
        if ($newSourceDir)
        {
            $Config.Paths.SourceDir = $newSourceDir
        }

        Write-WarningLog '【项目信息】'
        $newAuthor = Read-Host "作者 [当前: $($Config.Project.Author)]"
        if ($newAuthor)
        {
            $Config.Project.Author = $newAuthor
        }

        $newOriginalTitle = Read-Host "原作品名 [当前: $($Config.Project.OriginalTitle)]"
        if ($newOriginalTitle)
        {
            $Config.Project.OriginalTitle = $newOriginalTitle
        }

        $newChineseTitle = Read-Host "中文译名 [当前: $($Config.Project.ChineseTitle)]"
        if ($newChineseTitle)
        {
            $Config.Project.ChineseTitle = $newChineseTitle
        }

        Write-WarningLog '原文简介（按 Ctrl+D 结束输入）：'
        $newOriginalOverviewLines = @()
        while ($true)
        {
            $line = $host.ui.ReadLine()
            if (-not $line -or $line -eq [char]0x04)
            {
                break
            }
            $newOriginalOverviewLines += $line
        }
        if ($newOriginalOverviewLines.Count -gt 0)
        {
            $Config.Project.OriginalOverview = $newOriginalOverviewLines -join "`n"
        }

        Write-WarningLog '中文简介（按 Ctrl+D 结束输入）：'
        $newChineseOverviewLines = @()
        while ($true)
        {
            $line = $host.ui.ReadLine()
            if (-not $line -or $line -eq [char]0x04)
            {
                break
            }
            $newChineseOverviewLines += $line
        }
        if ($newChineseOverviewLines.Count -gt 0)
        {
            $Config.Project.ChineseOverview = $newChineseOverviewLines -join "`n"
        }

        return Confirm-ProjectConfiguration -Config $Config
    }
}

Export-ModuleMember -Function @(
    'Get-Configuration',
    'Reset-Configuration',
    'Test-ConfigurationInitialized',
    'Confirm-ProjectConfiguration'
)
