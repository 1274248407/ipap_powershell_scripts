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
    System.IO.FileInfo（输出零个或多个无文字图文件对象）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Select-NonTextImage
{
    # 豁免 PSUseOutputTypeCorrectly：动态集合变量 return 的静态推断为 Object[]，
    # 与元素类型语义声明 [OutputType([System.IO.FileInfo])] 无法匹配（规则缺陷，官方 issue #1471）
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '')]
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
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
        # 记录错误现场后显式抛出强类型异常，中断本函数（Write-LogEntry 为纯日志函数）
        $ErrorMessage = "源目录不存在: $SourceDir"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    # 使用预排序图片或重新扫描
    if ($PreSortedImages -and $PreSortedImages.Count -gt 0)
    {
        $allFiles = $PreSortedImages
    }
    else
    {
        $allFiles = @(Get-ImageFile -Path $SourceDir -SupportedFormats $SupportedImageFormats | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
    }
    $subFolders = @(Get-ChildItem -LiteralPath $SourceDir -Directory)

    # 展示扫描结果
    Write-LogEntry -Level Info -Message '=== 无文字图处理 ==='
    Write-LogEntry -Level Info -Message "检测到 source_dir 下有 $($allFiles.Count) 张图片文件"

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

    Write-LogEntry -Level Info -Message ''
    Write-LogEntry -Level Info -Message '请选择无文字图来源：'

    # 展示选项
    for ($i = 0; $i -lt $options.Count; $i++)
    {
        Write-LogEntry -Level Info -Message "  [$($i + 1)] $($options[$i])"
    }

    # 展示图片排序预览（前 5 张和后 5 张）
    if ($allFiles.Count -gt 0)
    {
        $previewCount = [math]::Min(5, $allFiles.Count)
        $firstNames = ($allFiles[0..($previewCount - 1)] | ForEach-Object { $PSItem.Name }) -join ', '
        $lastNames = ($allFiles[($allFiles.Count - $previewCount)..($allFiles.Count - 1)] | ForEach-Object { $PSItem.Name }) -join ', '
        Write-LogEntry -Level Info -Message ''
        Write-LogEntry -Level Info -Message '图片排序预览（已按自然排序）：'
        Write-LogEntry -Level Info -Message "  前 $previewCount 张: $firstNames"
        # 所有的图片至少要大于10张
        if ($allFiles.Count -gt $previewCount * 2)
        {
            Write-LogEntry -Level Info -Message "  后 $previewCount 张: $lastNames"
        }
    }

    # 获取用户选择
    [int]$choice = 0
    while ($choice -lt 1 -or $choice -gt $options.Count)
    {
        p
        try
        {
            [int]$choice = Read-Host "请输入选项 (1-$($options.Count))"
        }
        catch
        {
            Write-LogEntry -Level Warning -Message '请输入有效的数字'
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
                    Write-LogEntry -Level Info -Message '用户跳过无文字图处理'
                    return
                }
            }
            catch
            {
                Write-LogEntry -Level Warning -Message '请输入有效的数字'
            }
        }

        # 取第 startIndex 张及之后的图片（1-based 索引）
        $nonTextImages = @($allFiles[($startIndex - 1)..($allFiles.Count - 1)])
        Write-LogEntry -Level Info -Message "已选择从第 $startIndex 张开始的 $($nonTextImages.Count) 张作为无文字图"
    }
    # 模式 2：选择子文件夹
    elseif ($choice -eq 2 -and $subFolders.Count -gt 0)
    {
        Write-LogEntry -Level Info -Message ''
        Write-LogEntry -Level Info -Message '可用的子文件夹：'

        for ($i = 0; $i -lt $subFolders.Count; $i++)
        {
            $folderPath = $subFolders[$i].FullName
            $folderImageCount = @(Get-ChildItem -LiteralPath $folderPath -File | Where-Object {
                    Test-SupportedImageFormat -File $PSItem -SupportedFormats $SupportedImageFormats
                }).Count
            Write-LogEntry -Level Info -Message "  [$($i + 1)] $($subFolders[$i].Name)/ (包含 $folderImageCount 张图片)"
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
                Write-LogEntry -Level Warning -Message '请输入有效的数字'
            }
        }

        $selectedFolder = $subFolders[$folderChoice - 1].FullName
        $nonTextImages = @(Get-ImageFile -Path $selectedFolder -SupportedFormats $SupportedImageFormats | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
        Write-LogEntry -Level Info -Message "已选择文件夹: $selectedFolder，包含 $($nonTextImages.Count) 张无文字图"
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
                Write-LogEntry -Level Warning -Message "路径不存在: $customPath，请重新输入"
            }
        }

        $nonTextImages = @(Get-ImageFile -Path $customPath -SupportedFormats $SupportedImageFormats | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
        Write-LogEntry -Level Info -Message "已选择自定义路径: $customPath，包含 $($nonTextImages.Count) 张无文字图"
    }
    # 模式 4：跳过
    else
    {
        Write-LogEntry -Level Info -Message '用户跳过无文字图处理'
        return
    }

    # 验证是否有图片
    if ($nonTextImages.Count -eq 0)
    {
        Write-LogEntry -Level Warning -Message '未找到任何无文字图'
        return
    }

    return $nonTextImages
}

