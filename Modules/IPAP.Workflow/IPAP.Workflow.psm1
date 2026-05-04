<#
.SYNOPSIS
    IPAP 工作流主模块
.DESCRIPTION
    提供完整的 IPAP 工作流执行逻辑，包括环境初始化、项目创建、图片分析和处理。
#>

# Workflow 模块依赖 IPAP.Core、IPAP.ImageProcessor、IPAP.ProjectManager
# 这些模块由 Main.ps1 统一导入，不需要重复导入

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

        # Get source directory first
        if (-not $SourceDir)
        {
            $SourceDir = Read-Host 'Enter source image directory'
        }

        # Analyze images first to verify there are images
        $imageInfo = Get-ImageInfo -SourceDir $SourceDir

        if ($imageInfo.Count -gt 0)
        {
            # Get project brief information (returns briefText and projectName)
            $briefText, $ProjectName = Get-ProjectBriefInfo

            # Create project structure using the projectName from Get-ProjectBriefInfo
            $projectDir = New-ProjectStructure -BaseDir $BaseDir -ProjectName $ProjectName

            if ($projectDir)
            {
                Write-InfoLog "Project initialization successful: $projectDir"

                # Copy source images to raw_source directory
                $rawSourceDir = Join-Path $projectDir '02_Preprocessing' 'raw_source'
                Write-InfoLog "Copying source images to $rawSourceDir"
            
                try
                {
                    # 使用 -LiteralPath 处理包含特殊字符的路径
                    Get-ChildItem -LiteralPath $SourceDir -File | Where-Object { $Global:SupportedImageFormats -contains $PSItem.Extension } | Copy-Item -Destination $rawSourceDir -Force
                    # 统计已复制的图片文件数量
                    $copiedCount = (Get-ChildItem -LiteralPath $rawSourceDir -File | Where-Object { $Global:SupportedImageFormats -contains $PSItem.Extension }).Count
                    # 记录日志，输出已复制的图片数量
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
                New-ReadmeFile -ProjectDir $projectDir -ProjectName $ProjectName -ImageCount $imageInfo.Count -NeedUpscale $needUpscale -UpscaleRatio 2
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
            else
            {
                Write-ErrorLog 'Project initialization failed'
            }
        }
        else
        {
            Write-WarningLog 'No images found in source directory, workflow terminated'
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
    'Start-IPAPWorkflow'
)
