<#
.SYNOPSIS
    IPAP 工作流核心基础模块
.DESCRIPTION
    提供日志系统、配置解析和通用工具函数。
#>

$ScriptRoot = $PSScriptRoot

$Global:BinPath = Join-Path $ScriptRoot '..\..\bin'
$Global:ConfigPath = Join-Path $ScriptRoot '..\..\config.toml'
$Global:TomlJsonExePath = Join-Path $Global:BinPath 'tomljson.exe'
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

$PoShLogPath = Join-Path $ScriptRoot '..\..\vendor\PoShLog'
Import-Module -Name $PoShLogPath -Force -Scope Global



<#
.SYNOPSIS
    读取配置文件
.DESCRIPTION
    从指定路径读取 config.toml 配置文件，使用 tomljson.exe 解析并返回配置哈希表。
    若配置文件不存在、tomljson.exe 不存在或解析失败，返回默认配置。
.PARAMETER ConfigPath
    (string) 配置文件路径，默认为全局变量 ConfigPath。
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

    if (-not (Test-Path $ConfigPath))
    {
        Write-WarningLog 'Configuration file not found, using default settings'
        return $Global:DefaultSettings
    }

    if (-not (Test-Path $Global:TomlJsonExePath))
    {
        Write-WarningLog 'tomljson.exe not found, using default settings'
        return $Global:DefaultSettings
    }

    try
    {
        $jsonOutput = & $Global:TomlJsonExePath $ConfigPath
        $config = $jsonOutput | ConvertFrom-Json

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
        return $Global:DefaultSettings
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

    $exePath = Get-ChildItem -Path $SearchPath -Name 'realcugan-ncnn-vulkan.exe' -Recurse -ErrorAction SilentlyContinue

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
    'TomlJsonExePath',
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
