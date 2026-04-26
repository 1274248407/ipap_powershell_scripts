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
