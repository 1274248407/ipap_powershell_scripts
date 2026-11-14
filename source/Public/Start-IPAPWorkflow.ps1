<#
.SYNOPSIS
    主工作流函数
.DESCRIPTION
    执行完整的 IPAP 工作流，包括环境初始化、项目创建、图片分析和处理。
    支持交互式输入或参数指定，处理过程中若发生错误则记录日志并退出。
    使用 Get-ImageLevel 进行图片分级（Level 0/1/2），再用 Get-ProjectLevel 归并出项目统一等级；
    同一项目内全部页面按该等级整批处理，保证输出宽高一致。
    Level 0 不放大，但统一转码为 webp，使 02_Preprocessing 全目录格式一致。
    参数优先级：函数参数 > 配置文件 > 交互式输入。
.PARAMETER Config
    (IPAPConfiguration) 配置实例（可选），若未指定则从全局配置获取。
.PARAMETER BaseDir
    (string) 项目基础目录（可选），若未指定则从配置读取或交互式输入。
    每个来源先去除首尾空白再判空：纯空白等同于未提供；交互输入为空时抛
    [System.InvalidOperationException]。
.PARAMETER SourceDir
    (string) 源图片目录（可选），若未指定则从配置读取或交互式输入。
    规则与 BaseDir 相同。
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

function Start-IPAPWorkflow {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [IPAPConfiguration]$Config = $null,
        [string]$BaseDir = $null,
        [string]$SourceDir = $null
    )

    # 只有完整跑完处理与校验才置为 $true；无图片、用户取消或异常路径保持 $false
    [bool]$WorkflowCompleted = $false

    try {
        Write-LogEntry -Level Info -Message '正在初始化 IPAP 工作流...'

        # 获取配置实例
        if (-not $Config) {
            if (-not (Test-ConfigurationInitialized)) {
                throw [System.InvalidOperationException]::new('配置未初始化，请先调用 Get-Configuration')
            }
            $Config = Get-Configuration
        }

        # 参数优先级：函数参数 > 配置文件 > 交互式输入；每个来源先 Trim 再判空，
        # 避免纯空白参数跳过回退、直到 New-ProjectStructure 参数绑定阶段才失败
        $BaseDir = ([string]$BaseDir).Trim()
        if (-not $BaseDir) {
            $BaseDir = ([string]$Config.Paths.BaseProjectDir).Trim()
        }
        if (-not $BaseDir) {
            if (-not $PSCmdlet.ShouldProcess('IPAP 工作流', '读取缺失的基础目录输入')) {
                return
            }
            $BaseDir = ([string](Read-Host '请输入项目基础目录')).Trim()
            if (-not $BaseDir) {
                $ErrorMessage = '未提供基础目录（BaseDir），且配置与交互输入均为空'
                Write-LogEntry -Level Error -Message $ErrorMessage
                throw [System.InvalidOperationException]::new($ErrorMessage)
            }
        }

        $SourceDir = ([string]$SourceDir).Trim()
        if (-not $SourceDir) {
            $SourceDir = ([string]$Config.Paths.SourceDir).Trim()
        }
        if (-not $SourceDir) {
            if (-not $PSCmdlet.ShouldProcess('IPAP 工作流', '读取缺失的源图片目录输入')) {
                return
            }
            $SourceDir = ([string](Read-Host '请输入源图片目录')).Trim()
            if (-not $SourceDir) {
                $ErrorMessage = '未提供源图片目录（SourceDir），且配置与交互输入均为空'
                Write-LogEntry -Level Error -Message $ErrorMessage
                throw [System.InvalidOperationException]::new($ErrorMessage)
            }
        }

        # 这里会对图片进行排序，确保按顺序处理
        $imageInfo = Get-ImageInfo -SourceDir $SourceDir

        if ($imageInfo.Count -gt 0) {
            # 使用配置中的项目信息调用 Get-ProjectBriefInfo
            $briefText, $ProjectName = Get-ProjectBriefInfo `
                -Author $Config.Project.Author `
                -OriginalTitle $Config.Project.OriginalTitle `
                -ChineseTitle $Config.Project.ChineseTitle `
                -OriginalOverview $Config.Project.OriginalOverview `
                -ChineseOverview $Config.Project.ChineseOverview

            if ($PSCmdlet.ShouldProcess($ProjectName, '创建项目结构')) {
                $projectDir = New-ProjectStructure -BaseDir $BaseDir -ProjectName $ProjectName

                if ($projectDir) {
                    Write-LogEntry -Level Info -Message "项目初始化成功: $projectDir"

                    # 交互式选择无文字图（传入预排序图片避免重复排序）
                    $nonTextImages = Select-NonTextImage -SourceDir $SourceDir -SupportedImageFormats $Config.App.SupportedImageFormats -PreSortedImages $imageInfo.Images

                    # 分离有文字图和无文字图
                    $textImages = @()
                    if ($nonTextImages.Count -gt 0) {
                        $nonTextNames = @($nonTextImages | ForEach-Object { $PSItem.Name })
                        $textImages = @($imageInfo.Images | Where-Object { $nonTextNames -notcontains $PSItem.Name })
                    }
                    else {
                        $textImages = @($imageInfo.Images)
                    }

                    # 复制有文字图到 raw_source
                    $rawSourceDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing\raw_source'
                    Write-LogEntry -Level Info -Message "正在复制 $($textImages.Count) 张有文字图到 $rawSourceDir"

                    try {
                        foreach ($image in $textImages) {
                            Copy-Item -LiteralPath $image.FullName -Destination $rawSourceDir -Force
                        }
                        Write-LogEntry -Level Info -Message "已复制 $($textImages.Count) 张有文字图到 raw_source 目录"
                    }
                    catch {
                        # 记录上下文后抛出包装异常并保留 InnerException（禁止吞异常）
                        $ErrorMessage = "复制有文字图失败: $($PSItem.Exception.Message)"
                        Write-LogEntry -Level Error -Message $ErrorMessage
                        throw [System.IO.IOException]::new($ErrorMessage, $PSItem.Exception)
                    }

                    # 无文字图输出目录
                    $nonTextRawDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing\original_non_text_raw'

                    # 分析图片质量分级
                    $textImageLevels = @(Get-ImageLevel -Images $textImages)
                    $nonTextImageLevels = @()
                    if ($nonTextImages.Count -gt 0) {
                        $nonTextImageLevels = @(Get-ImageLevel -Images $nonTextImages)
                    }

                    # 项目统一等级：同一项目内所有页面必须同一档位，否则被放大的页面宽高会与未放大的页面不一致
                    [int]$ProjectLevel = Get-ProjectLevel `
                        -TextLevels @($textImageLevels | ForEach-Object { [int]$PSItem.Level }) `
                        -NonTextLevels @($nonTextImageLevels | ForEach-Object { [int]$PSItem.Level })

                    [string]$ProjectLevelText = switch ($ProjectLevel) {
                        0 { 'Level 0（已高清，不放大）' }
                        1 { 'Level 1（FFmpeg 1.2 倍锐化）' }
                        2 { 'Level 2（Real-CUGAN 2 倍超分）' }
                    }
                    Write-LogEntry -Level Info -Message "项目统一等级: $ProjectLevelText；有文字图 $($textImages.Count) 张，无文字图 $($nonTextImages.Count) 张"

                    # README 的分级明细按项目等级归位：整批页面都按同一档位处理，
                    # 因此把该类别的全部图片放进与项目等级对应的数组，而不是按单图等级拆开
                    $textLevel1Levels = $ProjectLevel -eq 1 ? $textImageLevels : @()
                    $textLevel2Levels = $ProjectLevel -eq 2 ? $textImageLevels : @()
                    $nonTextLevel1Levels = $ProjectLevel -eq 1 ? $nonTextImageLevels : @()
                    $nonTextLevel2Levels = $ProjectLevel -eq 2 ? $nonTextImageLevels : @()

                    # 判断是否需要高清化：只有项目统一等级 > 0 才放大
                    [bool]$needUpscale = $ProjectLevel -gt 0

                    # 一次性生成 README（包含有文字图和无文字图的高清化详情）
                    New-ReadmeFile -ProjectDir $projectDir -ProjectName $ProjectName -ImageCount $imageInfo.Count -NeedUpscale:$needUpscale -UpscaleRatio $Config.App.UpscaleRatio -BriefText $briefText -Level1ImageLevels $textLevel1Levels -Level2ImageLevels $textLevel2Levels -NonTextLevel1ImageLevels $nonTextLevel1Levels -NonTextLevel2ImageLevels $nonTextLevel2Levels

                    $preprocessingDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing'
                    $maxWorkers = $Config.App.MaxWorkers

                    # 按项目统一等级整批路由：同项目不允许一部分页面放大、另一部分不放大
                    if ($ProjectLevel -eq 1) {
                        if ($textImages.Count -gt 0) {
                            Write-LogEntry -Level Info -Message "有文字图: 处理 $($textImages.Count) 张轻度模糊图片 (FFmpeg 锐化)"
                            $textResult = Invoke-ParallelUpscale -Images $textImages -OutputDir $preprocessingDir -Engine 'FFmpeg' -MaxWorkers $maxWorkers
                            Write-LogEntry -Level Info -Message "有文字图 Level 1 完成: 成功=$($textResult.SuccessCount), 失败=$($textResult.FailedCount)"
                        }

                        if ($nonTextImages.Count -gt 0) {
                            Write-LogEntry -Level Info -Message "无文字图: 处理 $($nonTextImages.Count) 张轻度模糊图片 (FFmpeg 锐化)"
                            $nonTextResult = Invoke-ParallelUpscale -Images $nonTextImages -OutputDir $nonTextRawDir -Engine 'FFmpeg' -MaxWorkers $maxWorkers
                            Write-LogEntry -Level Info -Message "无文字图 Level 1 完成: 成功=$($nonTextResult.SuccessCount), 失败=$($nonTextResult.FailedCount)"
                        }
                    }
                    elseif ($ProjectLevel -eq 2) {
                        if (-not $Config.Tools.RealCuganExePath) {
                            $level2Count = $textImages.Count + $nonTextImages.Count
                            Write-LogEntry -Level Warning -Message "项目等级为 Level 2: $level2Count 张图片需要 Real-CUGAN 处理，但未找到可执行文件"
                        }
                        else {
                            $modelPath = $Config.App.ModelSelect

                            if ($textImages.Count -gt 0) {
                                Write-LogEntry -Level Info -Message "有文字图: 处理 $($textImages.Count) 张重度模糊图片 (Real-CUGAN)"
                                $textResult = Invoke-ParallelUpscale -Images $textImages -OutputDir $preprocessingDir -Engine 'RealCugan' -MaxWorkers $maxWorkers -ModelPath $modelPath
                                Write-LogEntry -Level Info -Message "有文字图 Level 2 完成: 成功=$($textResult.SuccessCount), 失败=$($textResult.FailedCount)"
                            }

                            if ($nonTextImages.Count -gt 0) {
                                Write-LogEntry -Level Info -Message "无文字图: 处理 $($nonTextImages.Count) 张重度模糊图片 (Real-CUGAN)"
                                $nonTextResult = Invoke-ParallelUpscale -Images $nonTextImages -OutputDir $nonTextRawDir -Engine 'RealCugan' -MaxWorkers $maxWorkers -ModelPath $modelPath
                                Write-LogEntry -Level Info -Message "无文字图 Level 2 完成: 成功=$($nonTextResult.SuccessCount), 失败=$($nonTextResult.FailedCount)"
                            }
                        }
                    }
                    else {
                        # Level 0：不放大，但统一转码为 webp，保证 02_Preprocessing 全目录格式一致
                        if ($textImages.Count -gt 0) {
                            Write-LogEntry -Level Info -Message "有文字图: 转码 $($textImages.Count) 张为 webp（不放大）"
                            $textResult = Invoke-ParallelUpscale -Images $textImages -OutputDir $preprocessingDir -Engine 'Webp' -MaxWorkers $maxWorkers
                            Write-LogEntry -Level Info -Message "有文字图 Level 0 完成: 成功=$($textResult.SuccessCount), 失败=$($textResult.FailedCount)"
                        }

                        if ($nonTextImages.Count -gt 0) {
                            Write-LogEntry -Level Info -Message "无文字图: 转码 $($nonTextImages.Count) 张为 webp（不放大）"
                            $nonTextResult = Invoke-ParallelUpscale -Images $nonTextImages -OutputDir $nonTextRawDir -Engine 'Webp' -MaxWorkers $maxWorkers
                            Write-LogEntry -Level Info -Message "无文字图 Level 0 完成: 成功=$($nonTextResult.SuccessCount), 失败=$($nonTextResult.FailedCount)"
                        }
                    }

                    # 验证产出：数量取该类别全部图片数，扩展名必须统一为 webp
                    if ($textImages.Count -gt 0) {
                        $null = Test-UpscaleResult -ExpectedCount $textImages.Count -OutputDir $preprocessingDir -OutputFormat 'webp'
                    }
                    if ($nonTextImages.Count -gt 0) {
                        $null = Test-UpscaleResult -ExpectedCount $nonTextImages.Count -OutputDir $nonTextRawDir -OutputFormat 'webp'
                    }

                    # 处理与校验全部通过后才标记完成，提示音只在真正跑完时播放
                    $WorkflowCompleted = $true
                }
                else {
                    # 记录错误现场后显式抛出强类型异常，由外层 catch 捕获记录
                    $ErrorMessage = '项目初始化失败'
                    Write-LogEntry -Level Error -Message $ErrorMessage
                    throw [System.InvalidOperationException]::new($ErrorMessage)
                }
            }
        }
        else {
            Write-LogEntry -Level Warning -Message '源目录中没有图片，工作流终止'
        }
    }
    catch {
        # 顶层统一记录错误后重抛，保证进程退出码非零（供 CI/调度器感知失败）
        Write-LogEntry -Level Error -Message "执行过程中发生错误: $($PSItem.Exception.Message)"
        throw $PSItem
    }

    # 提示音只在完整跑完时播放：无图片、用户取消或异常路径保持安静
    if ($WorkflowCompleted) {
        Invoke-CompletionSound
    }
}

