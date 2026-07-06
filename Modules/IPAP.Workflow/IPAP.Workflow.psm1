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
                    Write-InfoLog "项目初始化成功: $projectDir"

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
                    Write-InfoLog "正在复制 $($textImages.Count) 张有文字图到 $rawSourceDir"

                    try
                    {
                        foreach ($image in $textImages)
                        {
                            Copy-Item -LiteralPath $image.FullName -Destination $rawSourceDir -Force
                        }
                        Write-InfoLog "已复制 $($textImages.Count) 张有文字图到 raw_source 目录"
                    }
                    catch
                    {
                        Write-ErrorLog "复制有文字图失败: $($PSItem.Exception.Message)"
                        throw
                    }

                    # 复制无文字图到 original_non_text_raw
                    $nonTextRawDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing\original_non_text_raw'
                    if ($nonTextImages.Count -gt 0)
                    {
                        Write-InfoLog "正在复制 $($nonTextImages.Count) 张无文字图到 $nonTextRawDir"

                        try
                        {
                            foreach ($image in $nonTextImages)
                            {
                                Copy-Item -LiteralPath $image.FullName -Destination $nonTextRawDir -Force
                            }
                            Write-InfoLog "已复制 $($nonTextImages.Count) 张无文字图到 original_non_text_raw 目录"
                        }
                        catch
                        {
                            Write-ErrorLog "复制无文字图失败: $($PSItem.Exception.Message)"
                            throw
                        }
                    }

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
                    New-ReadmeFile -ProjectDir $projectDir -ProjectName $ProjectName -ImageCount $imageInfo.Count -NeedUpscale $needUpscale -UpscaleRatio $Config.App.UpscaleRatio -BriefText $briefText -Level1ImageLevels $textLevel1Levels -Level2ImageLevels $textLevel2Levels -NonTextLevel1ImageLevels $nonTextLevel1Levels -NonTextLevel2ImageLevels $nonTextLevel2Levels

                    $preprocessingDir = Join-Path -Path $projectDir -ChildPath '02_Preprocessing'
                    $maxWorkers = $Config.App.MaxWorkers

                    # 高清化有文字图
                    if ($textLevel1Images.Count -gt 0)
                    {
                        Write-InfoLog "有文字图 Level 1: 处理 $($textLevel1Images.Count) 张轻度模糊图片 (FFmpeg 锐化)"
                        $result1 = Invoke-ParallelUpscale -Images $textLevel1Images -OutputDir $preprocessingDir -Engine 'FFmpeg' -MaxWorkers $maxWorkers
                        Write-InfoLog "有文字图 Level 1 完成: 成功=$($result1.SuccessCount), 失败=$($result1.FailedCount)"
                    }

                    if ($textLevel2Images.Count -gt 0)
                    {
                        if ($Config.Tools.RealCuganExePath)
                        {
                            Write-InfoLog "有文字图 Level 2: 处理 $($textLevel2Images.Count) 张重度模糊图片 (Real-CUGAN)"
                            $modelPath = $Config.App.ModelSelect
                            $result2 = Invoke-ParallelUpscale -Images $textLevel2Images -OutputDir $preprocessingDir -Engine 'RealCugan' -MaxWorkers $maxWorkers -ModelPath $modelPath
                            Write-InfoLog "有文字图 Level 2 完成: 成功=$($result2.SuccessCount), 失败=$($result2.FailedCount)"
                        }
                        else
                        {
                            Write-WarningLog "有文字图 Level 2: $($textLevel2Images.Count) 张图片需要 Real-CUGAN 处理，但未找到可执行文件"
                        }
                    }

                    # 高清化无文字图
                    if ($nonTextLevel1Images.Count -gt 0)
                    {
                        Write-InfoLog "无文字图 Level 1: 处理 $($nonTextLevel1Images.Count) 张轻度模糊图片 (FFmpeg 锐化)"
                        $result3 = Invoke-ParallelUpscale -Images $nonTextLevel1Images -OutputDir $nonTextRawDir -Engine 'FFmpeg' -MaxWorkers $maxWorkers
                        Write-InfoLog "无文字图 Level 1 完成: 成功=$($result3.SuccessCount), 失败=$($result3.FailedCount)"
                    }

                    if ($nonTextLevel2Images.Count -gt 0)
                    {
                        if ($Config.Tools.RealCuganExePath)
                        {
                            Write-InfoLog "无文字图 Level 2: 处理 $($nonTextLevel2Images.Count) 张重度模糊图片 (Real-CUGAN)"
                            $modelPath = $Config.App.ModelSelect
                            $result4 = Invoke-ParallelUpscale -Images $nonTextLevel2Images -OutputDir $nonTextRawDir -Engine 'RealCugan' -MaxWorkers $maxWorkers -ModelPath $modelPath
                            Write-InfoLog "无文字图 Level 2 完成: 成功=$($result4.SuccessCount), 失败=$($result4.FailedCount)"
                        }
                        else
                        {
                            Write-WarningLog "无文字图 Level 2: $($nonTextLevel2Images.Count) 张图片需要 Real-CUGAN 处理，但未找到可执行文件"
                        }
                    }

                    # 验证有文字图处理结果
                    $textTotalProcessed = $textLevel1Images.Count + $textLevel2Images.Count
                    if ($textTotalProcessed -gt 0)
                    {
                        Test-UpscaleResult -ExpectedCount $textTotalProcessed -OutputDir $preprocessingDir
                    }
                    else
                    {
                        Write-InfoLog '所有有文字图均为高清 (Level 0)，跳过预处理'
                    }

                    # 验证无文字图处理结果
                    $nonTextTotalProcessed = $nonTextLevel1Images.Count + $nonTextLevel2Images.Count
                    if ($nonTextTotalProcessed -gt 0)
                    {
                        Test-UpscaleResult -ExpectedCount $nonTextTotalProcessed -OutputDir $nonTextRawDir
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
    交互式选择无文字图
.DESCRIPTION
    交互式引导用户指定无文字图来源，返回无文字图文件对象数组。
    支持多种无文字图来源：起始编号、子文件夹选择、自定义路径或跳过。
    仅负责选择，不负责复制或处理。
    若提供 PreSortedImages 参数，则直接使用已排序的图片列表，避免重复排序。
.PARAMETER SourceDir
    (string, Mandatory) 源图片目录路径。
.PARAMETER SupportedImageFormats
    (string[], Mandatory) 支持的图片格式列表。
.PARAMETER PreSortedImages
    (array, Optional) 预排序的图片文件对象数组。若提供则直接使用，不再重新扫描和排序。
.EXAMPLE
    $nonTextImages = Select-NonTextImage -SourceDir "D:\Images" -SupportedImageFormats @('.jpg', '.png')
    交互式选择无文字图并返回文件对象数组。
.EXAMPLE
    $imageInfo = Get-ImageInfo -SourceDir "D:\Images"
    $nonTextImages = Select-NonTextImage -SourceDir "D:\Images" -SupportedImageFormats @('.jpg', '.png') -PreSortedImages $imageInfo.Images
    使用预排序的图片列表，避免重复排序。
.INPUTS
    无
.OUTPUTS
    array (System.IO.FileInfo 对象数组，跳过时返回空数组)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Select-NonTextImage
{
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [string[]]$SupportedImageFormats,
        [Parameter(Mandatory = $false)]
        [array]$PreSortedImages = $null
    )

    # 检查源目录是否存在
    if (-not (Test-Path -LiteralPath $SourceDir))
    {
        Write-ErrorLog "源目录不存在: $SourceDir"
        return @()
    }

    # 使用预排序图片或重新扫描
    if ($PreSortedImages -and $PreSortedImages.Count -gt 0)
    {
        $allFiles = $PreSortedImages
    }
    else
    {
        $allFiles = @(Get-ChildItem -LiteralPath $SourceDir -File | Where-Object {
                Test-SupportedImageFormat -File $PSItem -SupportedFormats $SupportedImageFormats
            } | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
    }
    $subFolders = @(Get-ChildItem -LiteralPath $SourceDir -Directory)

    # 展示扫描结果
    Write-InfoLog '=== 无文字图处理 ==='
    Write-InfoLog "检测到 source_dir 下有 $($allFiles.Count) 张图片文件"

    # 构建选项菜单
    $options = @()
    $options += '输入起始编号（如从第 N 张开始是无文字图）'

    # 只在有子文件夹时展示选项 2
    if ($subFolders.Count -gt 0)
    {
        $options += '选择子文件夹'
    }

    $options += '输入自定义路径'
    $options += '跳过（没有无文字图）'

    Write-InfoLog ''
    Write-InfoLog '请选择无文字图来源：'

    # 展示选项
    for ($i = 0; $i -lt $options.Count; $i++)
    {
        Write-InfoLog "  [$($i + 1)] $($options[$i])"
    }

    # 展示图片排序预览（前 5 张和后 5 张）
    if ($allFiles.Count -gt 0)
    {
        $previewCount = [math]::Min(5, $allFiles.Count)
        $firstNames = ($allFiles[0..($previewCount - 1)] | ForEach-Object { $PSItem.Name }) -join ', '
        $lastNames = ($allFiles[($allFiles.Count - $previewCount)..($allFiles.Count - 1)] | ForEach-Object { $PSItem.Name }) -join ', '
        Write-InfoLog ''
        Write-InfoLog '图片排序预览（已按自然排序）：'
        Write-InfoLog "  前 $previewCount 张: $firstNames"
        # 所有的图片至少要大于10张
        if ($allFiles.Count -gt $previewCount * 2)
        {
            Write-InfoLog "  后 $previewCount 张: $lastNames"
        }
    }

    # 获取用户选择
    [int]$choice = 0
    while ($choice -lt 1 -or $choice -gt $options.Count)
    {
        try
        {
            [int]$choice = Read-Host "请输入选项 (1-$($options.Count))"
        }
        catch
        {
            Write-WarningLog '请输入有效的数字'
        }
    }

    $nonTextImages = @()

    # 模式 1：输入起始编号
    if ($choice -eq 1)
    {
        [int]$startIndex = 0
        while ($startIndex -lt 1 -or $startIndex -gt $allFiles.Count)
        {
            try
            {
                [int]$startIndex = Read-Host "请输入从第几张开始是无文字图 (1-$($allFiles.Count)，输入 0 跳过)"
                if ($startIndex -eq 0)
                {
                    Write-InfoLog '用户跳过无文字图处理'
                    return @()
                }
            }
            catch
            {
                Write-WarningLog '请输入有效的数字'
            }
        }

        # 取第 startIndex 张及之后的图片（1-based 索引）
        $nonTextImages = @($allFiles[($startIndex - 1)..($allFiles.Count - 1)])
        Write-InfoLog "已选择从第 $startIndex 张开始的 $($nonTextImages.Count) 张作为无文字图"
    }
    # 模式 2：选择子文件夹
    elseif ($choice -eq 2 -and $subFolders.Count -gt 0)
    {
        Write-InfoLog ''
        Write-InfoLog '可用的子文件夹：'

        for ($i = 0; $i -lt $subFolders.Count; $i++)
        {
            $folderPath = $subFolders[$i].FullName
            $folderImageCount = @(Get-ChildItem -LiteralPath $folderPath -File | Where-Object {
                    Test-SupportedImageFormat -File $PSItem -SupportedFormats $SupportedImageFormats
                }).Count
            Write-InfoLog "  [$($i + 1)] $($subFolders[$i].Name)/ (包含 $folderImageCount 张图片)"
        }

        [int]$folderChoice = 0
        while ($folderChoice -lt 1 -or $folderChoice -gt $subFolders.Count)
        {
            try
            {
                [int]$folderChoice = Read-Host "请选择无文字图文件夹 (1-$($subFolders.Count))"
            }
            catch
            {
                Write-WarningLog '请输入有效的数字'
            }
        }

        $selectedFolder = $subFolders[$folderChoice - 1].FullName
        $nonTextImages = @(Get-ChildItem -LiteralPath $selectedFolder -File | Where-Object {
                Test-SupportedImageFormat -File $PSItem -SupportedFormats $SupportedImageFormats
            } | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
        Write-InfoLog "已选择文件夹: $selectedFolder，包含 $($nonTextImages.Count) 张无文字图"
    }
    # 模式 3：输入自定义路径
    elseif ($choice -eq $options.Count - 1)
    {
        [string]$customPath = ''
        while (-not $customPath -or -not (Test-Path -LiteralPath $customPath))
        {
            $customPath = Read-Host '请输入无文字图文件夹路径'
            if (-not (Test-Path -LiteralPath $customPath))
            {
                Write-WarningLog "路径不存在: $customPath，请重新输入"
            }
        }

        $nonTextImages = @(Get-ChildItem -LiteralPath $customPath -File | Where-Object {
                Test-SupportedImageFormat -File $PSItem -SupportedFormats $SupportedImageFormats
            } | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
        Write-InfoLog "已选择自定义路径: $customPath，包含 $($nonTextImages.Count) 张无文字图"
    }
    # 模式 4：跳过
    else
    {
        Write-InfoLog '用户跳过无文字图处理'
        return @()
    }

    # 验证是否有图片
    if ($nonTextImages.Count -eq 0)
    {
        Write-WarningLog '未找到任何无文字图'
        return @()
    }

    return $nonTextImages
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

    $outputFiles = Get-ChildItem -LiteralPath $OutputDir -File | Where-Object {
        Test-SupportedImageFormat -File $PSItem
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
    'Select-NonTextImage',
    'Test-UpscaleResult'
)

