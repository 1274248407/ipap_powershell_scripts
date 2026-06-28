<#
.SYNOPSIS
    IPAP 工作流主模块
.DESCRIPTION
    提供完整的 IPAP 工作流执行逻辑，包括环境初始化、项目创建、图片分析和处理。
#>

# 使用 using module 确保 IPAPConfiguration 类型在模块解析阶段即可用
# 使用相对路径引用，避免依赖 PSModulePath 的注入时机
using module ..\IPAP.Configuration\IPAP.Configuration.psd1

<#
.SYNOPSIS
    主工作流函数
.DESCRIPTION
    执行完整的 IPAP 工作流，包括环境初始化、项目创建、图片分析和处理。
    支持交互式输入或参数指定，处理过程中若发生错误则记录日志并退出。
    使用 Get-ImageLevel 进行图片分级（Level 0/1/2），按级别分组并行处理。
    参数优先级：函数参数 > 配置文件 > 交互式输入。
.PARAMETER Config
    (IPAPConfiguration) 配置实例（可选），若未指定则从全局配置获取。
.PARAMETER BaseDir
    (string) 项目基础目录（可选），若未指定则从配置读取或交互式输入。
.PARAMETER SourceDir
    (string) 源图片目录（可选），若未指定则从配置读取或交互式输入。
.EXAMPLE
    Start-IPAPWorkflow
    执行完整的工作流，使用配置文件或交互式输入参数。
.EXAMPLE
    Start-IPAPWorkflow -Config $config -BaseDir "C:\Projects" -SourceDir "C:\Images"
    使用指定配置实例和参数执行工作流。
.INPUTS
    IPAPConfiguration
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Start-IPAPWorkflow
{
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [IPAPConfiguration]$Config = $null,
        [string]$BaseDir = $null,
        [string]$SourceDir = $null
    )

    try
    {
        Write-InfoLog '正在初始化 IPAP 工作流...'

        # 获取配置实例
        if (-not $Config)
        {
            if (-not (Test-ConfigurationInitialized))
            {
                throw [System.InvalidOperationException]::new('配置未初始化，请先调用 Get-Configuration')
            }
            $Config = Get-Configuration
        }

        # 参数优先级：函数参数 > 配置文件 > 交互式输入
        if (-not $BaseDir)
        {
            $BaseDir = $Config.Paths.BaseProjectDir
        }
        if (-not $BaseDir)
        {
            $BaseDir = Read-Host '请输入项目基础目录'
        }

        if (-not $SourceDir)
        {
            $SourceDir = $Config.Paths.SourceDir
        }
        if (-not $SourceDir)
        {
            $SourceDir = Read-Host '请输入源图片目录'
        }

        $imageInfo = Get-ImageInfo -SourceDir $SourceDir

        if ($imageInfo.Count -gt 0)
        {
            # 使用配置中的项目信息调用 Get-ProjectBriefInfo
            $briefText, $ProjectName = Get-ProjectBriefInfo `
                -Author $Config.Project.Author `
                -OriginalTitle $Config.Project.OriginalTitle `
                -ChineseTitle $Config.Project.ChineseTitle `
                -OriginalOverview $Config.Project.OriginalOverview `
                -ChineseOverview $Config.Project.ChineseOverview

            if ($PSCmdlet.ShouldProcess($ProjectName, '创建项目结构'))
            {
                $projectDir = New-ProjectStructure -BaseDir $BaseDir -ProjectName $ProjectName

                if ($projectDir)
                {
                    Write-InfoLog "项目初始化成功: $projectDir"

                    $rawSourceDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing\raw_source'
                    Write-InfoLog "正在复制源图片到 $rawSourceDir"

                    try
                    {
                        Get-ChildItem -LiteralPath $SourceDir -File | Where-Object { $Config.App.SupportedImageFormats -contains $PSItem.Extension } | Copy-Item -Destination $rawSourceDir -Force
                        $copiedCount = (Get-ChildItem -LiteralPath $rawSourceDir -File | Where-Object { $Config.App.SupportedImageFormats -contains $PSItem.Extension }).Count
                        if ($copiedCount -eq 0)
                        {
                            throw [System.IO.FileNotFoundException]::new('未找到任何支持的图片文件')
                        }
                        Write-InfoLog "已复制 $copiedCount 张图片到 raw_source 目录"
                    }
                    catch
                    {
                        Write-ErrorLog "复制图片失败: $($PSItem.Exception.Message)"
                        throw
                    }

                    # 逐张分析图片质量，返回分级结果（Level 0/1/2）
                    $imageLevels = Get-ImageLevel -Images $imageInfo.Images

                    $needUpscale = @($imageLevels | Where-Object { $PSItem.Level -gt 0 }).Count -gt 0
                    $level1Images = @($imageLevels | Where-Object { $PSItem.Level -eq 1 }) | ForEach-Object { $PSItem.Image }
                    $level2Images = @($imageLevels | Where-Object { $PSItem.Level -eq 2 }) | ForEach-Object { $PSItem.Image }

                    New-ReadmeFile -ProjectDir $projectDir -ProjectName $ProjectName -ImageCount $imageInfo.Count -NeedUpscale $needUpscale -UpscaleRatio $Config.App.UpscaleRatio -BriefText $briefText

                    $preprocessingDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing'
                    $maxWorkers = $Config.App.MaxWorkers

                    if ($level1Images.Count -gt 0)
                    {
                        Write-InfoLog "Level 1: 处理 $($level1Images.Count) 张轻度模糊图片 (FFmpeg 锐化)"
                        $result1 = Invoke-ParallelUpscale -Images $level1Images -OutputDir $preprocessingDir -Engine 'FFmpeg' -MaxWorkers $maxWorkers
                        Write-InfoLog "Level 1 完成: 成功=$($result1.SuccessCount), 失败=$($result1.FailedCount)"
                    }

                    if ($level2Images.Count -gt 0)
                    {
                        if ($Config.Tools.RealCuganExePath)
                        {
                            Write-InfoLog "Level 2: 处理 $($level2Images.Count) 张重度模糊图片 (Real-CUGAN)"
                            $modelPath = $Config.App.ModelSelect
                            $result2 = Invoke-ParallelUpscale -Images $level2Images -OutputDir $preprocessingDir -Engine 'RealCugan' -MaxWorkers $maxWorkers -ModelPath $modelPath
                            Write-InfoLog "Level 2 完成: 成功=$($result2.SuccessCount), 失败=$($result2.FailedCount)"
                        }
                        else
                        {
                            Write-WarningLog "Level 2: $($level2Images.Count) 张图片需要 Real-CUGAN 处理，但未找到可执行文件"
                        }
                    }

                    $totalProcessed = $level1Images.Count + $level2Images.Count
                    if ($totalProcessed -gt 0)
                    {
                        Test-UpscaleResult -ExpectedCount $totalProcessed -OutputDir $preprocessingDir
                    }
                    else
                    {
                        Write-InfoLog '所有图片均为高清 (Level 0)，跳过预处理'
                    }
                }
                else
                {
                    Write-ErrorLog '项目初始化失败'
                }
            }
        }
        else
        {
            Write-WarningLog '源目录中没有图片，工作流终止'
        }
    }
    catch
    {
        Write-ErrorLog "执行过程中发生错误: $($PSItem.Exception.Message)"
        throw $PSItem
    }
}

<#
.SYNOPSIS
    验证高清化处理结果
.DESCRIPTION
    检查输出目录中的图片数量是否与预期相符。
.PARAMETER ExpectedCount
    (int) 预期输出图片数量。
.PARAMETER OutputDir
    (string) 输出目录路径。
.EXAMPLE
    Test-UpscaleResult -ExpectedCount 10 -OutputDir "C:\Output"
.INPUTS
    无
.OUTPUTS
    bool
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Test-UpscaleResult
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [int]$ExpectedCount,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    if (-not (Test-Path -LiteralPath $OutputDir))
    {
        Write-ErrorLog "输出目录不存在: $OutputDir"
        return $false
    }

    # 从配置获取支持的图片格式
    $SupportedImageFormats = (Get-Configuration).App.SupportedImageFormats

    $outputFiles = Get-ChildItem -LiteralPath $OutputDir -File | Where-Object {
        $SupportedImageFormats -contains $PSItem.Extension.ToLower()
    }

    $actualCount = $outputFiles.Count
    $successRate = [math]::Round(($actualCount / $ExpectedCount) * 100, 1)

    if ($actualCount -eq $ExpectedCount)
    {
        Write-InfoLog "高清化处理成功完成。预期: $ExpectedCount, 实际: $actualCount (100%)"
        return $true
    }
    elseif ($actualCount -eq 0)
    {
        Write-ErrorLog '并行处理完全失败，未生成任何输出文件'
        return $false
    }
    else
    {
        $failedCount = $ExpectedCount - $actualCount
        Write-WarningLog "并行处理部分完成 - 预期: $ExpectedCount, 实际: $actualCount, 失败: $failedCount ($successRate%)"
        return $false
    }
}

Export-ModuleMember -Function @(
    'Start-IPAPWorkflow',
    'Test-UpscaleResult'
)

