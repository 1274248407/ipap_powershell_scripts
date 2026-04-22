<#
.SYNOPSIS
    IPAP 工作流主模块
.DESCRIPTION
    提供完整的 IPAP 工作流执行逻辑，包括环境初始化、项目创建、图片分析和处理。
#>

# Import dependent modules
$ScriptRoot = $PSScriptRoot
Import-Module "$ScriptRoot\..\IPAP.Core\IPAP.Core.psd1" -Force -Scope Global
Import-Module "$ScriptRoot\..\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1" -Force -Scope Global
Import-Module "$ScriptRoot\..\IPAP.ProjectManager\IPAP.ProjectManager.psd1" -Force -Scope Global

# Define helper functions
function Get-RealCuganExePath
{
    [CmdletBinding()]
    param (
        [string]$SearchPath = "$ScriptRoot\..\..\bin"
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
        [string]$ConfigPath = "$ScriptRoot\..\..\config.toml"
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Reading configuration file: $ConfigPath" -ForegroundColor Cyan

    $TomlJsonExePath = "$ScriptRoot\..\..\bin\tomljson.exe"
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

# Main workflow function
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

<#
.SYNOPSIS
    主工作流函数
.DESCRIPTION
    执行完整的 IPAP 工作流，包括环境初始化、项目创建、图片分析和处理。
.PARAMETER BaseDir
    项目基础目录（可选）。
.PARAMETER ProjectName
    项目名称（可选）。
.PARAMETER SourceDir
    源图片目录（可选）。
.EXAMPLE
    Start-IPAPWorkflow
    执行完整的工作流，交互式输入所有参数。
.EXAMPLE
    Start-IPAPWorkflow -BaseDir "C:\Projects" -ProjectName "Manga1" -SourceDir "C:\Images"
    使用指定参数执行工作流。
#>
function Start-IPAPWorkflow
{
    [CmdletBinding()]
    param (
        [string]$BaseDir = $null,
        [string]$ProjectName = $null,
        [string]$SourceDir = $null
    )

    try
    {
        # Initialize environment
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [INFO] Initializing IPAP workflow..." -ForegroundColor Cyan
        Initialize-Environment

        # Get base directory
        if (-not $BaseDir)
        {
            if ($Global:Settings.paths.base_project_dir)
            {
                $BaseDir = $Global:Settings.paths.base_project_dir
            }
            else
            {
                $BaseDir = Read-Host 'Enter project base directory'
            }
        }

        # Get project name
        if (-not $ProjectName)
        {
            $ProjectName = Read-Host 'Enter project name'
        }

        # Get project brief information
        $briefText, $projectNameFormatted = Get-ProjectBriefInfo

        # Create project structure
        $projectDir = New-ProjectStructure -BaseDir $BaseDir -ProjectName $projectNameFormatted

        if ($projectDir)
        {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$timestamp] [SUCCESS] Project initialization successful: $projectDir" -ForegroundColor Green

            # Get source directory
            if (-not $SourceDir)
            {
                $SourceDir = Read-Host 'Enter source image directory'
            }

            # Analyze images
            $imageInfo = Get-ImageInfo -SourceDir $SourceDir

            if ($imageInfo.Count -gt 0)
            {
                # Copy source images to raw_source directory
                $rawSourceDir = Join-Path $projectDir '02_Preprocessing' 'raw_source'
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Write-Host "[$timestamp] [INFO] Copying source images to $rawSourceDir" -ForegroundColor Cyan
                
                try
                {
                    $imageFormats = $Global:SupportedImageFormats | ForEach-Object { '*' + $_ }
                    Get-ChildItem -Path $SourceDir -Include $imageFormats -File | Copy-Item -Destination $rawSourceDir -Force
                    $copiedCount = (Get-ChildItem -Path $rawSourceDir -Include $imageFormats -File).Count
                    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    Write-Host "[$timestamp] [SUCCESS] Copied $copiedCount images to raw_source directory" -ForegroundColor Green
                }
                catch
                {
                    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    Write-Host "[$timestamp] [ERROR] Failed to copy images: $($_.Exception.Message)" -ForegroundColor Red
                }
                
                # Check if upscaling is needed
                $needUpscale = Test-NeedUpscale -AverageSize $imageInfo.AverageSize
                $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Write-Host "[$timestamp] [INFO] Upscaling needed: $needUpscale" -ForegroundColor Cyan

                # Create project documentation files
                New-ReadmeFile -ProjectDir $projectDir -ProjectName $projectNameFormatted -ImageCount $imageInfo.Count -NeedUpscale $needUpscale -UpscaleRatio 2
                New-TranslationFiles -ProjectDir $projectDir -BriefText $briefText

                # Perform upscaling if needed
                if ($needUpscale -and $Global:RealCuganExePath)
                {
                    $outputDir = Join-Path $projectDir '02_Preprocessing'
                    $modelPath = $Global:Settings.app_settings.model_select
                    $maxWorkers = $Global:Settings.app_settings.max_workers

                    # Test parallel processing
                    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    Write-Host "[$timestamp] [INFO] Testing parallel processing with $maxWorkers concurrency" -ForegroundColor Cyan
                    $result = Invoke-ParallelUpscale -Images $imageInfo.Images -OutputDir $outputDir -MaxWorkers $maxWorkers -ModelPath $modelPath

                    if ($result.SuccessCount -gt 0)
                    {
                        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        Write-Host "[$timestamp] [SUCCESS] Parallel processing test successful, success: $($result.SuccessCount), failed: $($result.FailedCount)" -ForegroundColor Green
                    }
                    else
                    {
                        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        Write-Host "[$timestamp] [ERROR] Parallel processing test failed" -ForegroundColor Red
                    }
                }
            }
        }
        else
        {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$timestamp] [ERROR] Project initialization failed" -ForegroundColor Red
        }

    }
    catch
    {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] Error during execution: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Start-IPAPWorkflow',
    'Initialize-Environment'
)
