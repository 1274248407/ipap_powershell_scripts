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
        $jsonOutput = & $TomlJsonExePath $ConfigPath
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
