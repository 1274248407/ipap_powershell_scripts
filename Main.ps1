<#
.SYNOPSIS
IPAP Workflow - 漫画翻译准备自动化工具启动脚本

.DESCRIPTION
启动 IPAP 工作流，导入必要的模块并执行主工作流。

.NOTES
Author: IPAP Team
Version: 1.0.0
Date: 2026-04-14
#>

# Ensure PowerShell 7 or above
if ($PSVersionTable.PSVersion.Major -lt 7)
{
    Write-ErrorLog 'Error: PowerShell 7 or above is required'
    exit 1
}
# 设置控制台输出编码为 UTF-8，以支持特殊字符（如 ✓）
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptRoot = $PSScriptRoot

# Import PoShLog module
$PoShLogPath = Join-Path $ScriptRoot 'vendor\PoShLog'
Import-Module -Name $PoShLogPath -Force -Scope Global

# Initialize Logger in the Global scope so all modules can see it
& {
    $Global:Logger = New-Logger |
        Set-MinimumLevel -Value Verbose |
        Add-SinkConsole |
        Start-Logger
}

Write-InfoLog '✓ PoShLog module imported'


# Import modules
Write-InfoLog 'Importing IPAP modules...'

# Import IPAP.Core module
$coreModulePath = "$ScriptRoot\Modules\IPAP.Core\IPAP.Core.psd1"
Import-Module $coreModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.Core module imported'

# Import IPAP.ImageProcessor module
$imageProcessorModulePath = "$ScriptRoot\Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1"
Import-Module $imageProcessorModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.ImageProcessor module imported'

# Import IPAP.ProjectManager module
$projectManagerModulePath = "$ScriptRoot\Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1"
Import-Module $projectManagerModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.ProjectManager module imported'  

# Import IPAP.Workflow module
$workflowModulePath = "$ScriptRoot\Modules\IPAP.Workflow\IPAP.Workflow.psd1"

Import-Module $workflowModulePath -Force -Scope Global
Write-InfoLog '✓ IPAP.Workflow module imported'


# Define helper functions directly in Main.ps1
<#
.SYNOPSIS
    查找 realcugan-ncnn-vulkan.exe 可执行文件路径
.DESCRIPTION
    在指定搜索路径中递归查找 realcugan-ncnn-vulkan.exe 文件，返回完整路径或 $null。
    若未找到文件则记录错误日志。
.PARAMETER SearchPath
    (string) 搜索目录路径，默认为脚本目录下的 bin 文件夹。
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
        [string]$SearchPath = "$ScriptRoot\bin"
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
    调用 tomljson.exe 解析配置文件
.DESCRIPTION
    调用 tomljson.exe 外部程序来解析 TOML 配置文件并返回 JSON 输出。
.PARAMETER ExePath
    tomljson.exe 的路径
.PARAMETER ConfigPath
    要解析的 TOML 配置文件路径
.EXAMPLE
    $json = Invoke-TomlJsonExe -ExePath 'C:\bin\tomljson.exe' -ConfigPath 'config.toml'
.INPUTS
    无
.OUTPUTS
    string
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Invoke-TomlJsonExe
{
    [CmdletBinding()]
    param (
        [string]$ExePath,
        [string]$ConfigPath
    )
    
    & $ExePath $ConfigPath
}

<#
.SYNOPSIS
    读取配置文件
.DESCRIPTION
    从指定路径读取 config.toml 配置文件，使用 tomljson.exe 解析并返回配置哈希表。
    若配置文件不存在、tomljson.exe 不存在或解析失败，返回默认配置。
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
        [string]$ConfigPath = "$ScriptRoot\config.toml"
    )

    Write-InfoLog "Reading configuration file: $ConfigPath"

    $TomlJsonExePath = "$ScriptRoot\bin\tomljson.exe"
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

    if (-not (Test-Path $ConfigPath))
    {
        Write-WarningLog 'Configuration file not found, using default settings'
        return $DefaultSettings
    }

    if (-not (Test-Path $TomlJsonExePath))
    {
        Write-WarningLog 'tomljson.exe not found, using default settings'
        return $DefaultSettings
    }

    try
    {
        $jsonOutput = Invoke-TomlJsonExe -ExePath $TomlJsonExePath -ConfigPath $ConfigPath
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
        return $DefaultSettings
    }
}

# Define Initialize-Environment function directly in Main.ps1
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

    # Locate realcugan-ncnn-vulkan.exe
    $Global:RealCuganExePath = Get-RealCuganExePath
    if (-not $Global:RealCuganExePath)
    {
        Write-WarningLog 'Cannot locate realcugan-ncnn-vulkan.exe, upscaling functionality will be unavailable'
    }

    # Load configuration
    $Global:Settings = Get-Config

    Write-InfoLog 'Environment initialization completed'
}

# Only execute main workflow when running directly (not when imported)
# $MyInvocation.InvocationName is empty or '.' when script is dot-sourced
if ($MyInvocation.InvocationName -eq '' -or $MyInvocation.InvocationName -eq '.')
{
    # Script is being imported (dot-sourced), don't execute main workflow
    Write-Verbose 'Main.ps1 imported as module, skipping auto-execution'
}
else
{
    # Script is running directly, execute main workflow
    # Check if Start-IPAPWorkflow function is available
    if (Get-Command Start-IPAPWorkflow -ErrorAction SilentlyContinue)
    {
        Write-InfoLog "`nAll modules imported successfully!"
        
        # Test Initialize-Environment function
        Write-InfoLog 'Testing Initialize-Environment function...'
        if (Get-Command -Name 'Initialize-Environment' -ErrorAction SilentlyContinue)
        {
            Write-InfoLog '✓ Initialize-Environment function found'
        }
        else
        {
            Write-ErrorLog '✗ Initialize-Environment function not found'
            exit 1
        }
        
        Write-InfoLog "Starting IPAP Workflow...`n"

        # Execute main workflow
        Start-IPAPWorkflow
    }
    else
    {
        Write-ErrorLog '✗ Start-IPAPWorkflow function not found'
        exit 1
    }
}
