<#
.SYNOPSIS
    IPAP 工作流核心基础模块
.DESCRIPTION
    提供日志系统、配置解析和通用工具函数。
#>

$ScriptRoot = $PSScriptRoot

$Global:BinPath = Join-Path $ScriptRoot '..\bin'
$Global:ConfigPath = Join-Path $ScriptRoot '..\config.toml'
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

<#
.SYNOPSIS
    输出带时间戳和颜色的日志信息
.DESCRIPTION
    根据指定的日志级别输出不同颜色的日志信息，包含时间戳和日志级别标识。
.PARAMETER Message
    要输出的日志消息内容。
.PARAMETER Level
    日志级别，支持 INFO、SUCCESS、WARNING、ERROR。默认为 INFO。
.EXAMPLE
    Write-Log "Starting process"
    输出 INFO 级别的日志。
#>
function Write-Log
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    switch ($Level)
    {
        'INFO'
        {
            Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan
        }
        'SUCCESS'
        {
            Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green
        }
        'WARNING'
        {
            Write-Host "[$timestamp] [WARNING] $Message" -ForegroundColor Yellow
        }
        'ERROR'
        {
            Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red
        }
        default
        {
            Write-Host "[$timestamp] [$Level] $Message"
        }
    }
}

function Get-Config
{
    [CmdletBinding()]
    param (
        [string]$ConfigPath = $Global:ConfigPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Reading configuration file: $ConfigPath" -ForegroundColor Cyan

    if (-not (Test-Path $ConfigPath))
    {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [WARNING] Configuration file not found, using default settings" -ForegroundColor Yellow
        return $Global:DefaultSettings
    }

    if (-not (Test-Path $Global:TomlJsonExePath))
    {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [WARNING] tomljson.exe not found, using default settings" -ForegroundColor Yellow
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

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [SUCCESS] Configuration file parsed successfully" -ForegroundColor Green
        return $configHash
    }
    catch
    {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] Configuration file parsing failed: $($_.Exception.Message), using default settings" -ForegroundColor Red
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

<#
.SYNOPSIS
    初始化环境
.DESCRIPTION
    定位 realcugan-ncnn-vulkan.exe 并加载配置文件，为后续操作做准备。
.EXAMPLE
    Initialize-Environment
    初始化运行环境。
#>
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
    'Write-Log',
    'Get-Config',
    'Get-NaturalSortKey',
    'Get-RealCuganExePath',
    'Initialize-Environment'
)
