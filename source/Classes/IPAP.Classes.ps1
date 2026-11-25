<#
.SYNOPSIS
    IPAP 配置类集合
.DESCRIPTION
    包含 IPAP 全部配置类：PathConfiguration、ToolConfiguration、ProjectConfiguration、
    ApplicationConfiguration 和 IPAPConfiguration。
    注意：PowerShell 类的属性类型与方法签名在解析期绑定，存在相互引用的类
    必须位于同一解析单元（同一文件），故合并为一个文件维护。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
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

class PathConfiguration {
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
        先规范化 ProjectRoot（去除首尾空白），再验证其非空且为已存在的目录（指向文件也拒绝）。
    .PARAMETER ProjectRoot
        项目根目录路径
    .PARAMETER BaseProjectDir
        漫画/翻译项目工作区的基准目录（可选）
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
    PathConfiguration([string]$ProjectRoot, [string]$BaseProjectDir = $null, [string]$SourceDir = $null) {
        # 先规范化：Windows 会把尾部空格当无意义，存下来会导致 ProjectRoot 与 BinPath 字符串不一致
        # 注意：类方法内不能给与属性同名的参数赋值（会被解析成属性赋值），故用局部变量
        [string]$NormalizedRoot = $ProjectRoot.Trim()
        if ([string]::IsNullOrWhiteSpace($NormalizedRoot)) {
            throw [System.ArgumentException]::new('ProjectRoot 不能为空')
        }
        # -PathType Container：指向文件时 Test-Path 也为真，必须显式要求目录
        if (-not (Test-Path -LiteralPath $NormalizedRoot -PathType Container)) {
            throw [System.IO.DirectoryNotFoundException]::new("ProjectRoot 目录不存在或不是目录: $NormalizedRoot")
        }
        $this.ProjectRoot = $NormalizedRoot
        $this.BaseProjectDir = $BaseProjectDir
        $this.BinPath = Join-Path $NormalizedRoot 'bin'
        $this.ConfigPath = Join-Path $NormalizedRoot 'config.toml'
        $this.SourceDir = $SourceDir
    }

}


<#
.SYNOPSIS
    工具配置类
.DESCRIPTION
    管理外部工具的可执行文件路径，包括 FFmpeg、FFprobe 和 Real-CUGAN。
    支持配置路径解析和 PATH 环境变量回退机制。
.EXAMPLE
        $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

class ToolConfiguration {
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
        PathConfig 为空时抛出 ArgumentException；'paths' 区块存在但不是字典类型时抛出 ArgumentException。
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
    ToolConfiguration([PathConfiguration]$PathConfig, [hashtable]$Settings) {
        # PathConfig 是所有工具路径的解析基准；为空时无法 Join-Path 或定位 bin 目录
        if ($null -eq $PathConfig) {
            throw [System.ArgumentException]::new('PathConfig 不能为空')
        }
        $this.PathConfig = $PathConfig

        # 与 ProjectConfiguration/ApplicationConfiguration 一致：paths 区块类型非法时抛逻辑异常
        [object]$pathsValue = $Settings.paths ?? @{}
        if ($pathsValue -isnot [System.Collections.IDictionary]) {
            [string]$actualType = $pathsValue.GetType().Name
            throw [System.ArgumentException]::new("配置项 'paths' 必须是 IDictionary 类型，当前值类型为 '$actualType'")
        }
        # 有序字典等非 Hashtable 的字典实现脱壳为 Hashtable，后续才能安全读取键值
        [hashtable]$pathsSettings = $pathsValue -is [hashtable] ? $pathsValue : [hashtable]$pathsValue

        $this.FfmpegExePath = $this.ResolveToolPath($pathsSettings.ffmpeg_exe, 'ffmpeg')
        $this.FfprobeExePath = $this.ResolveToolPath($pathsSettings.ffprobe_exe, 'ffprobe')
        $this.RealCuganExePath = $this.ResolveRealCuganPath($pathsSettings.realcugan_exe)
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
    .OUTPUTS
        string
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    hidden [string] ResolveToolPath([string]$ConfiguredPath, [string]$CommandName) {
        # 空配置值直接置为 null，非空时拼成完整路径
        $FullPath = [string]::IsNullOrWhiteSpace($ConfiguredPath) ? $null : (Join-Path $this.PathConfig.ProjectRoot $ConfiguredPath)
        # 配置路径必须指向真实文件，指向目录等非文件目标时视为未命中
        if ($FullPath -and (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
            return $FullPath
        }

        # 配置路径缺失或不存在时回退到 PATH 环境变量查找
        $Command = Get-Command $CommandName -ErrorAction SilentlyContinue
        return $Command ? $Command.Source : $null
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
    hidden [string] ResolveRealCuganPath([string]$ConfiguredPath) {
        # 空配置值直接置为 null，非空时拼成完整路径
        $FullPath = [string]::IsNullOrWhiteSpace($ConfiguredPath) ? $null : (Join-Path $this.PathConfig.ProjectRoot $ConfiguredPath)
        # 配置路径必须指向真实文件，指向目录等非文件目标时视为未命中
        if ($FullPath -and (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
            return $FullPath
        }

        # 配置路径缺失或不存在时在 bin 目录中递归查找
        $ExeName = 'realcugan-ncnn-vulkan.exe'
        $Found = Get-ChildItem -LiteralPath $this.PathConfig.BinPath -Name $ExeName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        return $Found ? (Join-Path $this.PathConfig.BinPath $Found) : $null
    }

}


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

class ProjectConfiguration {
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
        当 'project' 键存在但其值不是字典（IDictionary）时，抛出 ArgumentException；
        有序字典（[ordered]）等非 Hashtable 的字典实现会被自动转换为 Hashtable。
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
    ProjectConfiguration([hashtable]$Settings) {
        # 先初始化所有属性为空字符串
        $this.Author = ''
        $this.OriginalTitle = ''
        $this.ChineseTitle = ''
        $this.OriginalOverview = ''
        $this.ChineseOverview = ''

        # 然后从配置读取值
        if ($Settings -and $Settings.ContainsKey('project')) {
            $projectSettings = $Settings.project

            # 'project' 键存在但不是字典类型时，抛出逻辑异常，避免系统异常直接穿透给调用方
            if ($projectSettings -isnot [System.Collections.IDictionary]) {
                $actualType = $null -eq $projectSettings ? 'null' : $projectSettings.GetType().Name
                throw [System.ArgumentException]::new("配置项 'project' 必须是 IDictionary 类型，当前值类型为 '$actualType'")
            }

            # 有序字典等非 Hashtable 的字典实现脱壳为 Hashtable，后续才能安全使用 ContainsKey（与 ReadConfigFile 的子配置块约定一致）
            $projectSettings = $projectSettings -is [hashtable] ? $projectSettings : [hashtable]$projectSettings

            if ($projectSettings.ContainsKey('author')) { $this.Author = $projectSettings.author }
            if ($projectSettings.ContainsKey('original_title')) { $this.OriginalTitle = $projectSettings.original_title }
            if ($projectSettings.ContainsKey('chinese_title')) { $this.ChineseTitle = $projectSettings.chinese_title }
            if ($projectSettings.ContainsKey('original_overview')) { $this.OriginalOverview = $projectSettings.original_overview }
            if ($projectSettings.ContainsKey('chinese_overview')) { $this.ChineseOverview = $projectSettings.chinese_overview }
        }
    }
}


<#
.SYNOPSIS
    应用配置类
.DESCRIPTION
    管理应用程序的运行参数，包括支持的图片格式、最大工作线程数、
    超时设置、模型选择、放大参数和 WebP 输出选项。
.EXAMPLE
        $appConfig = [ApplicationConfiguration]::new($settings)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

class ApplicationConfiguration {
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

    # WebP 输出质量（ffmpeg -quality，0-100；Real-CUGAN 输出不受此值控制）
    [int]$WebpQuality

    # 高细节判定阈值（边缘图 PNG 大小，KB）
    [double]$HighDetailThreshold

    # 中细节判定阈值（边缘图 PNG 大小，KB）
    [double]$MediumDetailThreshold

    # AI 补全用的 chat completions 地址；留空表示不启用
    [string]$AiEndpoint

    # AI 模型名
    [string]$AiModel

    # 存放 API Key 的环境变量名（密钥不写入配置文件）
    [string]$AiApiKeyEnv

    # 直接写在 config.toml 里的 API Key；环境变量优先，这里只是备用
    [string]$AiApiKey

    # 采样温度（0 = 每次结果一致，越大越发散）
    [double]$AiTemperature

    # 单次回复的最大 token 数（推理模型会把思考也算在内）
    [int]$AiMaxTokens

    # AI 请求超时（秒）
    [int]$AiTimeoutSec

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
    ApplicationConfiguration([hashtable]$Settings) {
        $this.Settings = $Settings

        # 从配置读取值并钳制到有效值域（区块缺失回退空哈希表，值缺失回退默认值，[math]::Clamp 钳制上下限）
        $appSettings = [ApplicationConfiguration]::GetSettingsBlock($Settings.app_settings, 'app_settings')
        $this.SupportedImageFormats = $appSettings.supported_image_formats ?? @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
        $this.MaxWorkers = [ApplicationConfiguration]::TryIntConvert($appSettings.max_workers ?? 0, 'max_workers')
        $this.UpscaleTimeoutSec = [ApplicationConfiguration]::TryIntConvert($appSettings.upscale_timeout_sec ?? 3600, 'upscale_timeout_sec')
        # 超时时间必须为正整数，无效值回退到默认 3600 秒
        $this.UpscaleTimeoutSec = $this.UpscaleTimeoutSec -lt 1 ? 3600 : $this.UpscaleTimeoutSec
        $this.ModelSelect = $appSettings.model_select ?? 'models-se'

        $upscaleSettings = [ApplicationConfiguration]::GetSettingsBlock($Settings.upscale, 'upscale')
        $this.UpscaleRatio = [int][math]::Clamp([ApplicationConfiguration]::TryIntConvert($upscaleSettings.upscale_ratio, 'upscale_ratio') ?? 2, 1, 4)   # Real-CUGAN -s: 1/2/3/4
        $this.NoiseLevel = [int][math]::Clamp([ApplicationConfiguration]::TryIntConvert($upscaleSettings.noise_level, 'noise_level') ?? 0, -1, 3)      # Real-CUGAN -n: -1~3

        $webpSettings = [ApplicationConfiguration]::GetSettingsBlock($Settings.webp, 'webp')
        $this.WebpQuality = [int][math]::Clamp([ApplicationConfiguration]::TryIntConvert($webpSettings.quality, 'quality') ?? 95, 0, 100)            # ffmpeg -quality: 0~100

        # 分级阈值：边缘图 PNG 大小（KB），用于 Level 0/1/2 判定
        $classifierSettings = [ApplicationConfiguration]::GetSettingsBlock($Settings.classifier, 'classifier')
        $this.HighDetailThreshold = [double][math]::Clamp([ApplicationConfiguration]::TryDoubleConvert($classifierSettings.high_detail, 'high_detail') ?? 6.0, 0.0, 1000.0)
        $this.MediumDetailThreshold = [double][math]::Clamp([ApplicationConfiguration]::TryDoubleConvert($classifierSettings.medium_detail, 'medium_detail') ?? 3.0, 0.0, 1000.0)
        # 中细节阈值不得高于高细节阈值，避免配置倒置导致 Level 0/2 不可达
        if ($this.MediumDetailThreshold -gt $this.HighDetailThreshold) {
            $this.MediumDetailThreshold = $this.HighDetailThreshold
        }

        # AI 补全：默认关闭（endpoint 为空即跳过）；密钥只从环境变量读，不落盘
        $aiSettings = [ApplicationConfiguration]::GetSettingsBlock($Settings.ai, 'ai')
        $this.AiEndpoint = [string]($aiSettings.endpoint ?? '')
        $this.AiModel = [string]($aiSettings.model ?? '')
        $this.AiApiKeyEnv = [string]($aiSettings.api_key_env ?? 'IPAP_AI_API_KEY')
        $this.AiApiKey = [string]($aiSettings.api_key ?? '')
        $this.AiTemperature = [double][math]::Clamp([ApplicationConfiguration]::TryDoubleConvert($aiSettings.temperature, 'temperature') ?? 0.0, 0.0, 2.0)
        $this.AiMaxTokens = [int][math]::Clamp([ApplicationConfiguration]::TryIntConvert($aiSettings.max_tokens, 'max_tokens') ?? 8192, 256, 65536)
        $this.AiTimeoutSec = [int][math]::Clamp([ApplicationConfiguration]::TryIntConvert($aiSettings.timeout_sec, 'timeout_sec') ?? 30, 1, 600)

        # MaxWorkers 不大于 0 时（0 = 自动检测，负数 = 无效值），按 CPU 核心数动态计算
        $this.MaxWorkers = $this.MaxWorkers -le 0 ? [math]::Max(1, [System.Environment]::ProcessorCount / 2) : $this.MaxWorkers
    }

    <#
    .SYNOPSIS
        安全获取配置区块
    .DESCRIPTION
        取出配置中指定的区块并校验其类型。
        区块缺失或为 $null 时回退为空哈希表，调用方无需再做空值判断；
        区块存在但不是字典类型时抛出 ArgumentException，避免下游属性访问穿透系统异常
        （与 ProjectConfiguration 对 'project' 区块的处置一致）。
    .PARAMETER Value
        待校验的配置区块值
    .PARAMETER BlockName
        配置区块名称，用于构造友好的错误信息
    .OUTPUTS
        System.Collections.IDictionary
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    hidden static [System.Collections.IDictionary] GetSettingsBlock([object]$Value, [string]$BlockName) {
        # 区块缺失时回退空哈希表
        if ($null -eq $Value) {
            return @{}
        }

        # 区块存在但不是字典类型时抛出逻辑异常，避免系统异常直接穿透给调用方
        if ($Value -isnot [System.Collections.IDictionary]) {
            $actualType = $Value.GetType().Name
            throw [System.ArgumentException]::new("配置项 '$BlockName' 必须是 IDictionary 类型，当前值类型为 '$actualType'")
        }

        return $Value
    }

    <#
    .SYNOPSIS
        安全整数转换
    .DESCRIPTION
        将配置值安全转换为 [int]，失败时抛出逻辑异常而非系统异常。
    .PARAMETER Value
        待转换的配置值
    .PARAMETER ParameterName
        参数名称，用于构造友好的错误信息
    .OUTPUTS
        int
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    hidden static [object] TryIntConvert([object]$Value, [string]$ParameterName) {
        if ($null -eq $Value) { return $null }
        $parsed = $null
        if ([int]::TryParse([string]$Value, [ref]$parsed)) {
            return $parsed
        }
        throw [System.ArgumentException]::new("配置项 '$ParameterName' 的值 '$Value' 不是有效的整数")
    }

    <#
    .SYNOPSIS
        安全浮点转换
    .DESCRIPTION
        将配置值安全转换为 [double]，失败时抛出逻辑异常而非系统异常。
        使用 InvariantCulture 解析，保证小数点在不同系统区域设置下行为一致。
    .PARAMETER Value
        待转换的配置值
    .PARAMETER ParameterName
        参数名称，用于构造友好的错误信息
    .OUTPUTS
        double
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    hidden static [object] TryDoubleConvert([object]$Value, [string]$ParameterName) {
        if ($null -eq $Value) { return $null }
        $parsed = 0.0
        if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            return $parsed
        }
        throw [System.ArgumentException]::new("配置项 '$ParameterName' 的值 '$Value' 不是有效的数值")
    }

}


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

class IPAPConfiguration {
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
    ) {
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
    static [IPAPConfiguration] Load([string]$ProjectRoot) {
        $loadedSettings = [IPAPConfiguration]::ReadConfigFile($ProjectRoot)
        # paths 分类可能整体缺失，?? 回退到空哈希表后可安全探测子键；子键存在与否用三元取值
        $pathsSettings = $loadedSettings['paths'] ?? @{}
        # 'paths' 键存在但不是字典类型时抛出逻辑异常，避免 ContainsKey 调用穿透系统异常（与 ProjectConfiguration 的处置一致）
        if ($pathsSettings -isnot [System.Collections.IDictionary]) {
            $actualType = $pathsSettings.GetType().Name
            throw [System.ArgumentException]::new("配置项 'paths' 必须是 IDictionary 类型，当前值类型为 '$actualType'")
        }
        $baseProjectDir = $pathsSettings.ContainsKey('base_project_dir') ? $pathsSettings.base_project_dir : $null
        $sourceDir = $pathsSettings.ContainsKey('source_dir') ? $pathsSettings.source_dir : $null
        $loadedPaths = [PathConfiguration]::new($ProjectRoot, $baseProjectDir, $sourceDir)
        $loadedTools = [ToolConfiguration]::new($loadedPaths, $loadedSettings)
        $loadedApp = [ApplicationConfiguration]::new($loadedSettings)
        $loadedProject = [ProjectConfiguration]::new($loadedSettings)
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
    hidden static [hashtable] ReadConfigFile([string]$ProjectRoot) {
        $configPath = Join-Path $ProjectRoot 'config.toml'
        $defaultSettings = @{
            paths        = @{ base_project_dir = ''; source_dir = ''; ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' }
            project      = @{ author = ''; original_title = ''; chinese_title = ''; original_overview = ''; chinese_overview = '' }
            app_settings = @{ supported_image_formats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'); max_workers = 8; upscale_timeout_sec = 3600; model_select = 'models-se' }
            upscale      = @{ upscale_ratio = 2; noise_level = 0 }
            webp         = @{ quality = 95 }
        }

        if (-not (Test-Path -LiteralPath $configPath)) {
            Write-LogEntry -Level Info -Message "配置文件不存在: $configPath，使用默认配置"
            return $defaultSettings
        }

        try {
            # 按优先级搜索 PSToml 模块：发布包 RequiredModules -> 构建输出 -> 全局已安装
            $PSTomlCandidates = @(
                (Join-Path $ProjectRoot 'RequiredModules\PSToml'),
                (Join-Path $ProjectRoot 'output\RequiredModules\PSToml')
            )
            foreach ($PSTomlPath in $PSTomlCandidates) {
                # 找到首个存在的 PSToml 副本即导入；该副本损坏时跳过，继续尝试下一个候选
                if (-not (Test-Path -LiteralPath $PSTomlPath)) {
                    continue
                }
                try {
                    # 不带 -Force：PSToml 已由 IPAP.psm1 在模块加载时导入到模块作用域，
                    # -Force 会先移除再重新导入，把模块作用域那份一起拆掉（v3.0.0 就这么坏的）
                    Import-Module $PSTomlPath -Scope Local -ErrorAction Stop
                    break
                }
                catch {
                    Write-LogEntry -Level Warning -Message "PSToml 模块导入失败，跳过候选路径: $PSTomlPath"
                    continue
                }
            }

            if (Get-Command 'ConvertFrom-Toml' -ErrorAction SilentlyContinue) {
                $content = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
                # 空文件（新建但未填写）等同于无配置：直接回退默认表，避免把 null 传给解析器
                if ([string]::IsNullOrWhiteSpace($content)) {
                    Write-LogEntry -Level Info -Message "配置文件为空: $configPath，使用默认配置"
                    return $defaultSettings
                }
                $parsedSettings = $null
                $parseError = $null
                try {
                    $parsedSettings = ConvertFrom-Toml -InputObject $content -ErrorAction Stop
                }
                catch {
                    $parseError = $PSItem
                }

                # 如果解析失败且错误与字符串转义有关，尝试自动修复 Windows 路径转义
                if (-not $parsedSettings -and $parseError -and $parseError.Exception.Message -match 'Unexpected escape character') {
                    Write-LogEntry -Level Warning -Message 'TOML 解析失败，检测到可能是 Windows 路径反斜杠转义问题，正在尝试自动修复...'
                    try {
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
                        foreach ($escape in $escapeMap.Keys) {
                            $protectedContent = $protectedContent.Replace($escape, $escapeMap[$escape])
                        }

                        $fixedContent = $protectedContent.Replace('\', '\\')
                        foreach ($escape in $escapeMap.Keys) {
                            $fixedContent = $fixedContent.Replace($escapeMap[$escape], $escape)
                        }
                        $parsedSettings = ConvertFrom-Toml -InputObject $fixedContent -ErrorAction Stop
                        Write-LogEntry -Level Warning -Message "自动修复成功。建议将 config.toml 中的 Windows 路径改为单引号字面量字符串，例如 source_dir = 'C:\\path\\to\\dir'"
                    }
                    catch {
                        throw [System.InvalidOperationException]::new("无法解析 config.toml: $($parseError.Exception.Message)。常见原因：Windows 路径使用了双引号但未正确转义反斜杠。请将路径改为单引号字面量字符串，例如 source_dir = 'C:\\path\\to\\dir'")
                    }
                }
                elseif ($parseError) {
                    throw [System.InvalidOperationException]::new("无法解析 config.toml: $($parseError.Exception.Message)")
                }

                $parsedHashtable = [hashtable]$parsedSettings
                #  为什么转换？ ConvertFrom-Toml 解析出来的子配置块默认是 OrderedDictionary（记住了顺序，但查找慢且不可修改），
                # 而本项目的其他代码（如 MergeSettings）习惯用 Hashtable（不记顺序，但查找极快且可随意修改）。
                # 循环在干嘛？ 遍历配置的每一个顶级分类（如 paths、project），如果发现它还是个有序字典，
                # 就把它“脱壳”换成哈希表，确保数据格式统一。
                # 注意：必须先复制 Keys 再循环，避免在枚举过程中修改集合。
                $topLevelKeys = @($parsedHashtable.Keys)
                foreach ($key in $topLevelKeys) {
                    if ($parsedHashtable[$key] -is [System.Collections.Specialized.OrderedDictionary]) {
                        $parsedHashtable[$key] = [hashtable]$parsedHashtable[$key]
                    }
                }
                return [IPAPConfiguration]::MergeSettings($parsedHashtable, $defaultSettings)
            }
            else {
                Write-LogEntry -Level Info -Message 'PSToml 模块未找到，使用默认配置'
                return $defaultSettings
            }
        }
        catch {
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
    hidden static [hashtable] MergeSettings([hashtable]$ParsedSettings, [hashtable]$DefaultSettings) {
        $merged = $DefaultSettings.Clone()

        # 如果用户配置和默认配置都有这个分类（比如 paths），且它们里面都嵌套着小配置项（哈希表），就进入第二层循环，逐个对比小项。
        # 这叫浅合并。比如默认配置里 paths 有 A、B、C 三个路径，用户只配了 A。这段代码会只把 A 替换成用户的，保留默认的 B 和 C。
        foreach ($key in $ParsedSettings.Keys) {
            if ($merged.ContainsKey($key)) {
                if ($merged[$key] -is [hashtable] -and $ParsedSettings[$key] -is [hashtable]) {
                    $parsedSubTable = [hashtable]$ParsedSettings[$key]
                    foreach ($subKey in $parsedSubTable.Keys) {
                        if ($merged[$key].ContainsKey($subKey)) {
                            $merged[$key][$subKey] = $parsedSubTable[$subKey]
                        }
                    }
                }
                # 如果当前键在默认配置里存在，但它不是嵌套的哈希表（比如只是一个数字或字符串），直接用用户的值覆盖默认值
                else {
                    $merged[$key] = $ParsedSettings[$key]
                }
            }
            # 如果用户写了一个默认配置里根本没有的键，直接把它加进合并表
            else {
                $merged[$key] = $ParsedSettings[$key]
            }
        }

        return $merged
    }
}


