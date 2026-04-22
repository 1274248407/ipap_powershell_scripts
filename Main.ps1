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
    Write-Host 'Error: PowerShell 7 or above is required' -ForegroundColor Red
    exit 1
}

# Set script root
$ScriptRoot = $PSScriptRoot

# Import modules
Write-Host 'Importing IPAP modules...'

# Import IPAP.Core module
$coreModulePath = "$ScriptRoot\Modules\IPAP.Core\IPAP.Core.psd1"
if (Test-Path $coreModulePath)
{
    Import-Module $coreModulePath -Force -Scope Global
    Write-Host '✓ IPAP.Core module imported'
}
else
{
    Write-Host '✗ IPAP.Core module not found' -ForegroundColor Red
    exit 1
}

# Import IPAP.ImageProcessor module
$imageProcessorModulePath = "$ScriptRoot\Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1"
if (Test-Path $imageProcessorModulePath)
{
    Import-Module $imageProcessorModulePath -Force -Scope Global
    Write-Host '✓ IPAP.ImageProcessor module imported'
}
else
{
    Write-Host '✗ IPAP.ImageProcessor module not found' -ForegroundColor Red
    exit 1
}

# Import IPAP.ProjectManager module
$projectManagerModulePath = "$ScriptRoot\Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1"
if (Test-Path $projectManagerModulePath)
{
    Import-Module $projectManagerModulePath -Force -Scope Global
    Write-Host '✓ IPAP.ProjectManager module imported'
}
else
{
    Write-Host '✗ IPAP.ProjectManager module not found' -ForegroundColor Red
    exit 1
}

# Import IPAP.Workflow module
$workflowModulePath = "$ScriptRoot\Modules\IPAP.Workflow\IPAP.Workflow.psd1"
if (Test-Path $workflowModulePath)
{
    Import-Module $workflowModulePath -Force -Scope Global
    Write-Host '✓ IPAP.Workflow module imported'
}
else
{
    Write-Host '✗ IPAP.Workflow module not found' -ForegroundColor Red
    exit 1
}

# Define helper functions directly in Main.ps1
function Get-RealCuganExePath
{
    [CmdletBinding()]
    param (
        [string]$SearchPath = "$ScriptRoot\bin"
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Searching for realcugan-ncnn-vulkan.exe..." -ForegroundColor Cyan

    $exePath = Get-ChildItem -Path $SearchPath -Name 'realcugan-ncnn-vulkan.exe' -Recurse -ErrorAction SilentlyContinue
    if ($exePath)
    {
        $fullPath = Join-Path $SearchPath $exePath
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [SUCCESS] Found realcugan-ncnn-vulkan.exe: $fullPath" -ForegroundColor Green
        return $fullPath
    }
    else
    {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] realcugan-ncnn-vulkan.exe not found" -ForegroundColor Red
        return $null
    }
}

function Get-Config
{
    [CmdletBinding()]
    param (
        [string]$ConfigPath = "$ScriptRoot\config.toml"
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Reading configuration file: $ConfigPath" -ForegroundColor Cyan

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
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [WARNING] Configuration file not found, using default settings" -ForegroundColor Yellow
        return $DefaultSettings
    }

    if (-not (Test-Path $TomlJsonExePath))
    {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [WARNING] tomljson.exe not found, using default settings" -ForegroundColor Yellow
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

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [SUCCESS] Configuration file parsed successfully" -ForegroundColor Green
        return $configHash
    }
    catch
    {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] Configuration file parsing failed: $($_.Exception.Message), using default settings" -ForegroundColor Red
        return $DefaultSettings
    }
}

# Define Initialize-Environment function directly in Main.ps1
function Initialize-Environment
{
    [CmdletBinding()]
    param()

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Initializing environment..." -ForegroundColor Cyan

    # Locate realcugan-ncnn-vulkan.exe
    $Global:RealCuganExePath = Get-RealCuganExePath
    if (-not $Global:RealCuganExePath)
    {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [WARNING] Cannot locate realcugan-ncnn-vulkan.exe, upscaling functionality will be unavailable" -ForegroundColor Yellow
    }

    # Load configuration
    $Global:Settings = Get-Config

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [SUCCESS] Environment initialization completed" -ForegroundColor Green
}

# Check if Start-IPAPWorkflow function is available
if (Get-Command Start-IPAPWorkflow -ErrorAction SilentlyContinue)
{
    Write-Host "`nAll modules imported successfully!" -ForegroundColor Green
    
    # Test Initialize-Environment function
    Write-Host 'Testing Initialize-Environment function...'
    if (Get-Command -Name 'Initialize-Environment' -ErrorAction SilentlyContinue)
    {
        Write-Host '✓ Initialize-Environment function found'
    }
    else
    {
        Write-Host '✗ Initialize-Environment function not found' -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Starting IPAP Workflow...`n"

    # Execute main workflow
    Start-IPAPWorkflow
}
else
{
    Write-Host '✗ Start-IPAPWorkflow function not found' -ForegroundColor Red
    exit 1
}
