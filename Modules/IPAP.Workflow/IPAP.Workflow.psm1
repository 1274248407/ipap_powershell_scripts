<#
.SYNOPSIS
    IPAP 工作流主模块
.DESCRIPTION
    提供完整的 IPAP 工作流执行逻辑，包括环境初始化、项目创建、图片分析和处理。
#>

# Import dependent modules
$ScriptRoot = $PSScriptRoot

$PoShLogPath = Join-Path $ScriptRoot '..\..\vendor\PoShLog'
if (Test-Path $PoShLogPath)
{
    Import-Module -Name $PoShLogPath -Force
}

Import-Module "$ScriptRoot\..\IPAP.Core\IPAP.Core.psd1" -Force -Scope Global
Import-Module "$ScriptRoot\..\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1" -Force -Scope Global
Import-Module "$ScriptRoot\..\IPAP.ProjectManager\IPAP.ProjectManager.psd1" -Force -Scope Global

# Define helper functions
<#
.SYNOPSIS
    查找 realcugan-ncnn-vulkan.exe 可执行文件路径
.DESCRIPTION
    在指定搜索路径中递归查找 realcugan-ncnn-vulkan.exe 文件，返回完整路径或 $null。
    若未找到文件则记录错误日志。
.PARAMETER SearchPath
    (string) 搜索目录路径，默认为项目根目录下的 bin 文件夹。
    （适用于所有参数集）
.EXAMPLE
    Get-RealCuganExePath
    在默认路径查找 realcugan-ncnn-vulkan.exe。
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
        [string]$SearchPath = "$ScriptRoot\..\..\bin"
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
    读取配置文件
.DESCRIPTION
    从指定路径读取 config.toml 配置文件，使用 tomljson.exe 解析并返回配置哈希表。
    若配置文件不存在、tomljson.exe 不存在或解析失败，返回默认配置。
.PARAMETER ConfigPath
    (string) 配置文件路径，默认为项目根目录下的 config.toml。
    （适用于所有参数集）
.EXAMPLE
    Get-Config
    读取默认配置文件。
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
        [string]$ConfigPath = "$ScriptRoot\..\..\config.toml"
    )

    Write-InfoLog "Reading configuration file: $ConfigPath"

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

# Main workflow function
<#
.SYNOPSIS
    初始化环境
.DESCRIPTION
    定位 realcugan-ncnn-vulkan.exe 并加载配置文件，为后续操作做准备。
    若无法定位可执行文件则记录警告日志，不影响后续流程。
.EXAMPLE
    Initialize-Environment
    初始化运行环境。
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

<#
.SYNOPSIS
    主工作流函数
.DESCRIPTION
    执行完整的 IPAP 工作流，包括环境初始化、项目创建、图片分析和处理。
    支持交互式输入或参数指定，处理过程中若发生错误则记录日志并退出。
.PARAMETER BaseDir
    (string) 项目基础目录（可选），若未指定则从配置读取或交互式输入。
    （适用于所有参数集）
.PARAMETER ProjectName
    (string) 项目名称（可选），若未指定则交互式输入。
    （适用于所有参数集）
.PARAMETER SourceDir
    (string) 源图片目录（可选），若未指定则交互式输入。
    （适用于所有参数集）
.EXAMPLE
    Start-IPAPWorkflow
    执行完整的工作流，交互式输入所有参数。
.EXAMPLE
    Start-IPAPWorkflow -BaseDir "C:\Projects" -ProjectName "Manga1" -SourceDir "C:\Images"
    使用指定参数执行工作流。
.INPUTS
    无
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
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
        Write-InfoLog 'Initializing IPAP workflow...'
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
            Write-InfoLog "Project initialization successful: $projectDir"

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
                Write-InfoLog "Copying source images to $rawSourceDir"
                
                try
                {
                    Get-ChildItem -Path $SourceDir -File | Where-Object { $Global:SupportedImageFormats -contains $PSItem.Extension } | Copy-Item -Destination $rawSourceDir -Force
                    $copiedCount = (Get-ChildItem -Path $rawSourceDir -File | Where-Object { $Global:SupportedImageFormats -contains $PSItem.Extension }).Count
                    Write-InfoLog "Copied $copiedCount images to raw_source directory"
                }
                catch
                {
                    Write-ErrorLog "Failed to copy images: $($PSItem.Exception.Message)"
                }
                
                # Check if upscaling is needed
                $needUpscale = Test-NeedUpscale -AverageSize $imageInfo.AverageSize
                Write-InfoLog "Upscaling needed: $needUpscale"

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
                    Write-InfoLog "Testing parallel processing with $maxWorkers concurrency"
                    $result = Invoke-ParallelUpscale -Images $imageInfo.Images -OutputDir $outputDir -MaxWorkers $maxWorkers -ModelPath $modelPath

                    if ($result.SuccessCount -gt 0)
                    {
                        Write-InfoLog "Parallel processing test successful, success: $($result.SuccessCount), failed: $($result.FailedCount)"
                    }
                    else
                    {
                        Write-ErrorLog 'Parallel processing test failed'
                    }
                }
            }
        }
        else
        {
            Write-ErrorLog 'Project initialization failed'
        }

    }
    catch
    {
        Write-ErrorLog "Error during execution: $($PSItem.Exception.Message)"
        exit 1
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Start-IPAPWorkflow',
    'Initialize-Environment'
)
