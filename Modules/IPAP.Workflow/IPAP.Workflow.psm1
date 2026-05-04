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

                    # Verify processing result by checking actual output files
                    Test-UpscaleResult -ExpectedCount $imageInfo.Count -OutputDir $outputDir -ProcessResult $result
                }
                else
                {
                    Write-InfoLog "Upscaling skipped - needUpscale: $needUpscale, RealCugan available: $($null -ne $Global:RealCuganExePath)"
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

<#
.SYNOPSIS
    验证图片高清化处理结果
.DESCRIPTION
    通过实际检查输出目录中的文件来验证高清化处理是否成功完成，支持分级日志输出，并对比函数返回结果。
.PARAMETER ExpectedCount
    (int, Mandatory) 预期处理的图片数量。
.PARAMETER OutputDir
    (string, Mandatory) 输出目录路径。
.PARAMETER ProcessResult
    (hashtable) Invoke-ParallelUpscale 的返回结果（可选，用于对比验证）。
.INPUTS
    无
.OUTPUTS
    bool (是否全部成功)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Test-UpscaleResult
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$ExpectedCount,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        
        [hashtable]$ProcessResult
    )

    $processedImages = Get-ChildItem -LiteralPath $OutputDir -File | Where-Object { $Global:SupportedImageFormats -contains $PSItem.Extension }
    $actualCount = $processedImages.Count

    $successRate = if ($ExpectedCount -gt 0) { [math]::Round($actualCount / $ExpectedCount * 100, 2) } else { 0 }

    if ($ProcessResult)
    {
        Write-InfoLog "Processing result vs actual files: reported success=$($ProcessResult.SuccessCount), actual=$actualCount"
    }

    if ($actualCount -eq $ExpectedCount -and $ExpectedCount -gt 0)
    {
        Write-InfoLog "Parallel processing completed successfully, all $ExpectedCount images processed (verified)"
        return $true
    }
    elseif ($actualCount -eq 0)
    {
        Write-ErrorLog 'Parallel processing failed completely, no output files generated'
        return $false
    }
    else
    {
        $failedCount = $ExpectedCount - $actualCount
        Write-WarningLog "Parallel processing partially completed - expected: $ExpectedCount, actual: $actualCount, failed: $failedCount ($successRate%)"
        return $false
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Start-IPAPWorkflow',
    'Test-UpscaleResult'
)
