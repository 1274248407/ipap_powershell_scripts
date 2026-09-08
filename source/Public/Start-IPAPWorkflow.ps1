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
        Write-LogEntry -Level Info -Message '正在初始化 IPAP 工作流...'

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
        # 这里会对图片进行排序，确保按顺序处理
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
                    Write-LogEntry -Level Info -Message "项目初始化成功: $projectDir"

                    # 交互式选择无文字图（传入预排序图片避免重复排序）
                    $nonTextImages = Select-NonTextImage -SourceDir $SourceDir -SupportedImageFormats $Config.App.SupportedImageFormats -PreSortedImages $imageInfo.Images

                    # 分离有文字图和无文字图
                    $textImages = @()
                    if ($nonTextImages.Count -gt 0)
                    {
                        $nonTextNames = @($nonTextImages | ForEach-Object { $PSItem.Name })
                        $textImages = @($imageInfo.Images | Where-Object { $nonTextNames -notcontains $PSItem.Name })
                    }
                    else
                    {
                        $textImages = @($imageInfo.Images)
                    }

                    # 复制有文字图到 raw_source
                    $rawSourceDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing\raw_source'
                    Write-LogEntry -Level Info -Message "正在复制 $($textImages.Count) 张有文字图到 $rawSourceDir"

                    try
                    {
                        foreach ($image in $textImages)
                        {
                            Copy-Item -LiteralPath $image.FullName -Destination $rawSourceDir -Force
                        }
                        Write-LogEntry -Level Info -Message "已复制 $($textImages.Count) 张有文字图到 raw_source 目录"
                    }
                    catch
                    {
                        # 记录上下文后抛出包装异常并保留 InnerException（禁止吞异常）
                        $ErrorMessage = "复制有文字图失败: $($PSItem.Exception.Message)"
                        Write-LogEntry -Level Error -Message $ErrorMessage
                        throw [System.IO.IOException]::new($ErrorMessage, $PSItem.Exception)
                    }

                    # 无文字图输出目录
                    $nonTextRawDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing\original_non_text_raw'

                    # 分析图片质量分级
                    $textImageLevels = Get-ImageLevel -Images $textImages
                    $textLevel1Levels = @($textImageLevels | Where-Object { $PSItem.Level -eq 1 })
                    $textLevel2Levels = @($textImageLevels | Where-Object { $PSItem.Level -eq 2 })
                    $textLevel1Images = @($textLevel1Levels | ForEach-Object { $PSItem.Image })
                    $textLevel2Images = @($textLevel2Levels | ForEach-Object { $PSItem.Image })

                    # 分析无文字图质量
                    $nonTextLevel1Levels = @()
                    $nonTextLevel2Levels = @()
                    $nonTextLevel1Images = @()
                    $nonTextLevel2Images = @()
                    if ($nonTextImages.Count -gt 0)
                    {
                        $nonTextImageLevels = Get-ImageLevel -Images $nonTextImages
                        $nonTextLevel1Levels = @($nonTextImageLevels | Where-Object { $PSItem.Level -eq 1 })
                        $nonTextLevel2Levels = @($nonTextImageLevels | Where-Object { $PSItem.Level -eq 2 })
                        $nonTextLevel1Images = @($nonTextLevel1Levels | ForEach-Object { $PSItem.Image })
                        $nonTextLevel2Images = @($nonTextLevel2Levels | ForEach-Object { $PSItem.Image })
                    }

                    # 判断是否需要高清化
                    $needUpscale = @($textLevel1Levels).Count -gt 0 -or @($textLevel2Levels).Count -gt 0 -or @($nonTextLevel1Levels).Count -gt 0 -or @($nonTextLevel2Levels).Count -gt 0

                    # 一次性生成 README（包含有文字图和无文字图的高清化详情）
                    New-ReadmeFile -ProjectDir $projectDir -ProjectName $ProjectName -ImageCount $imageInfo.Count -NeedUpscale:$needUpscale -UpscaleRatio $Config.App.UpscaleRatio -BriefText $briefText -Level1ImageLevels $textLevel1Levels -Level2ImageLevels $textLevel2Levels -NonTextLevel1ImageLevels $nonTextLevel1Levels -NonTextLevel2ImageLevels $nonTextLevel2Levels

                    $preprocessingDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing'
                    $maxWorkers = $Config.App.MaxWorkers

                    # 高清化有文字图
                    if ($textLevel1Images.Count -gt 0)
                    {
                        Write-LogEntry -Level Info -Message "有文字图 Level 1: 处理 $($textLevel1Images.Count) 张轻度模糊图片 (FFmpeg 锐化)"
                        $result1 = Invoke-ParallelUpscale -Images $textLevel1Images -OutputDir $preprocessingDir -Engine 'FFmpeg' -MaxWorkers $maxWorkers
                        Write-LogEntry -Level Info -Message "有文字图 Level 1 完成: 成功=$($result1.SuccessCount), 失败=$($result1.FailedCount)"
                    }

                    if ($textLevel2Images.Count -gt 0)
                    {
                        if ($Config.Tools.RealCuganExePath)
                        {
                            Write-LogEntry -Level Info -Message "有文字图 Level 2: 处理 $($textLevel2Images.Count) 张重度模糊图片 (Real-CUGAN)"
                            $modelPath = $Config.App.ModelSelect
                            $result2 = Invoke-ParallelUpscale -Images $textLevel2Images -OutputDir $preprocessingDir -Engine 'RealCugan' -MaxWorkers $maxWorkers -ModelPath $modelPath
                            Write-LogEntry -Level Info -Message "有文字图 Level 2 完成: 成功=$($result2.SuccessCount), 失败=$($result2.FailedCount)"
                        }
                        else
                        {
                            Write-LogEntry -Level Warning -Message "有文字图 Level 2: $($textLevel2Images.Count) 张图片需要 Real-CUGAN 处理，但未找到可执行文件"
                        }
                    }

                    # 高清化无文字图
                    if ($nonTextLevel1Images.Count -gt 0)
                    {
                        Write-LogEntry -Level Info -Message "无文字图 Level 1: 处理 $($nonTextLevel1Images.Count) 张轻度模糊图片 (FFmpeg 锐化)"
                        $result3 = Invoke-ParallelUpscale -Images $nonTextLevel1Images -OutputDir $nonTextRawDir -Engine 'FFmpeg' -MaxWorkers $maxWorkers
                        Write-LogEntry -Level Info -Message "无文字图 Level 1 完成: 成功=$($result3.SuccessCount), 失败=$($result3.FailedCount)"
                    }

                    if ($nonTextLevel2Images.Count -gt 0)
                    {
                        if ($Config.Tools.RealCuganExePath)
                        {
                            Write-LogEntry -Level Info -Message "无文字图 Level 2: 处理 $($nonTextLevel2Images.Count) 张重度模糊图片 (Real-CUGAN)"
                            $modelPath = $Config.App.ModelSelect
                            $result4 = Invoke-ParallelUpscale -Images $nonTextLevel2Images -OutputDir $nonTextRawDir -Engine 'RealCugan' -MaxWorkers $maxWorkers -ModelPath $modelPath
                            Write-LogEntry -Level Info -Message "无文字图 Level 2 完成: 成功=$($result4.SuccessCount), 失败=$($result4.FailedCount)"
                        }
                        else
                        {
                            Write-LogEntry -Level Warning -Message "无文字图 Level 2: $($nonTextLevel2Images.Count) 张图片需要 Real-CUGAN 处理，但未找到可执行文件"
                        }
                    }

                    # 复制不需要高清化的无文字图（Level 0）到目标目录
                    $nonTextLevel0Levels = @($nonTextImageLevels | Where-Object { $PSItem.Level -eq 0 })
                    $nonTextLevel0Images = @($nonTextLevel0Levels | ForEach-Object { $PSItem.Image })
                    if ($nonTextLevel0Images.Count -gt 0)
                    {
                        Write-LogEntry -Level Info -Message "无文字图 Level 0: 复制 $($nonTextLevel0Images.Count) 张高清图片到 original_non_text_raw 目录"

                        try
                        {
                            if (-not (Test-Path -LiteralPath $nonTextRawDir))
                            {
                                New-Item -ItemType Directory -Path $nonTextRawDir -Force | Out-Null
                            }
                            foreach ($image in $nonTextLevel0Images)
                            {
                                Copy-Item -LiteralPath $image.FullName -Destination $nonTextRawDir -Force
                            }
                            Write-LogEntry -Level Info -Message "已复制 $($nonTextLevel0Images.Count) 张 Level 0 无文字图到 original_non_text_raw 目录"
                        }
                        catch
                        {
                            # 记录上下文后抛出包装异常并保留 InnerException（禁止吞异常）
                            Write-LogEntry -Level Error -Message "复制 Level 0 无文字图失败: $($PSItem.Exception.Message)"
                            throw [System.IO.IOException]::new("复制 Level 0 无文字图失败: $($PSItem.Exception.Message)", $PSItem.Exception)
                        }
                    }

                    # 验证有文字图处理结果
                    $textTotalProcessed = $textLevel1Images.Count + $textLevel2Images.Count
                    if ($textTotalProcessed -gt 0)
                    {
                        $null = Test-UpscaleResult -ExpectedCount $textTotalProcessed -OutputDir $preprocessingDir
                    }
                    else
                    {
                        Write-LogEntry -Level Info -Message '所有有文字图均为高清 (Level 0)，跳过预处理'
                    }

                    # 验证无文字图处理结果
                    $nonTextTotalProcessed = $nonTextLevel1Images.Count + $nonTextLevel2Images.Count
                    if ($nonTextTotalProcessed -gt 0)
                    {
                        $null = Test-UpscaleResult -ExpectedCount $nonTextTotalProcessed -OutputDir $nonTextRawDir
                    }
                }
                else
                {
                    # 记录错误现场后显式抛出强类型异常，由外层 catch 捕获记录
                    $ErrorMessage = '项目初始化失败'
                    Write-LogEntry -Level Error -Message $ErrorMessage
                    throw [System.InvalidOperationException]::new($ErrorMessage)
                }
            }
        }
        else
        {
            Write-LogEntry -Level Warning -Message '源目录中没有图片，工作流终止'
        }
    }
    catch
    {
        # 顶层统一记录错误后重抛，保证进程退出码非零（供 CI/调度器感知失败）
        Write-LogEntry -Level Error -Message "执行过程中发生错误: $($PSItem.Exception.Message)"
        throw $PSItem
    }
}

