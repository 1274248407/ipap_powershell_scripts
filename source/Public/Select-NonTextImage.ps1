<#
.SYNOPSIS
    交互式选择无文字图
.DESCRIPTION
    交互式引导用户指定无文字图来源，返回无文字图文件对象数组。
    支持多种无文字图来源：起始编号、子文件夹选择、自定义路径或跳过。
    仅负责选择，不负责复制或处理。
    若提供 PreSortedImages 参数，则直接使用已排序的图片列表，避免重复排序。
    非交互环境（stdin 已 EOF）下，所有输入点均按「跳过」处理，不会无限重问。
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

function Select-NonTextImage {
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
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        # 记录错误现场后显式抛出强类型异常，中断本函数（Write-LogEntry 为纯日志函数）
        $ErrorMessage = "源目录不存在: $SourceDir"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    # 使用预排序图片或重新扫描
    if ($PreSortedImages -and $PreSortedImages.Count -gt 0) {
        $allFiles = $PreSortedImages
    }
    else {
        $allFiles = @(Get-ImageFile -Path $SourceDir -SupportedFormats $SupportedImageFormats | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
    }
    $subFolders = @(Get-ChildItem -LiteralPath $SourceDir -Directory)

    # 展示扫描结果
    Write-LogEntry -Level Info -Message '=== 无文字图处理 ==='
    Write-LogEntry -Level Info -Message "检测到 source_dir 下有 $($allFiles.Count) 张图片文件"

    # 先展示排序预览：用户要先看到「第 N 张是哪张」，才能决定起始编号或选哪个选项
    if ($allFiles.Count -gt 0) {
        $previewCount = [math]::Min(5, $allFiles.Count)
        $firstNames = ($allFiles[0..($previewCount - 1)] | ForEach-Object { $PSItem.Name }) -join ', '
        $firstLabel = $previewCount -eq 1 ? '第 1 张' : "第 1-$previewCount 张"
        Write-LogEntry -Level Info -Message ''
        Write-LogEntry -Level Info -Message '图片排序预览（已按自然排序，序号从 1 开始）：'
        Write-LogEntry -Level Info -Message "  ${firstLabel}: $firstNames"
        # 图片数量超过预览两倍时才展示末尾一段，避免首尾重叠
        if ($allFiles.Count -gt $previewCount * 2) {
            $lastStart = $allFiles.Count - $previewCount + 1
            $lastNames = ($allFiles[($lastStart - 1)..($allFiles.Count - 1)] | ForEach-Object { $PSItem.Name }) -join ', '
            Write-LogEntry -Level Info -Message "  第 $lastStart-$($allFiles.Count) 张: $lastNames"
        }
    }

    # 构建选项菜单
    $options = @()
    $options += '输入起始编号（如从第 N 张开始是无文字图）'

    # 只在有子文件夹时展示选项 2
    if ($subFolders.Count -gt 0) {
        $options += '选择子文件夹'
    }

    $options += '输入自定义路径'
    $options += '跳过（没有无文字图）'

    Write-LogEntry -Level Info -Message ''
    Write-LogEntry -Level Info -Message '请选择无文字图来源：'

    # 展示选项
    for ($i = 0; $i -lt $options.Count; $i++) {
        Write-LogEntry -Level Info -Message "  [$($i + 1)] $($options[$i])"
    }

    # 获取用户选择（非数字与越界输入均由 Read-NumberInRange 提示后重问）
    [Nullable[int]]$choice = Read-NumberInRange -Prompt "请输入选项 (1-$($options.Count))" -Min 1 -Max $options.Count
    # EOF：不再重问，按跳过处理
    if ($null -eq $choice) {
        Write-LogEntry -Level Warning -Message '未读到输入（非交互环境），按跳过处理'
        return
    }

    $nonTextImages = @()

    # 模式 1：输入起始编号
    if ($choice -eq 1) {
        # 合法范围为 0..Count：0 表示跳过
        [Nullable[int]]$startIndex = Read-NumberInRange -Prompt "请输入从第几张开始是无文字图 (1-$($allFiles.Count)，输入 0 跳过)" -Min 0 -Max $allFiles.Count
        if ($null -eq $startIndex) {
            Write-LogEntry -Level Warning -Message '未读到输入（非交互环境），按跳过处理'
            return
        }
        if ($startIndex -eq 0) {
            Write-LogEntry -Level Info -Message '用户跳过无文字图处理'
            return
        }

        # 取第 startIndex 张及之后的图片（1-based 索引）
        $nonTextImages = @($allFiles[($startIndex - 1)..($allFiles.Count - 1)])
        Write-LogEntry -Level Info -Message "已选择从第 $startIndex 张开始的 $($nonTextImages.Count) 张作为无文字图"
    }
    # 模式 2：选择子文件夹
    elseif ($choice -eq 2 -and $subFolders.Count -gt 0) {
        Write-LogEntry -Level Info -Message ''
        Write-LogEntry -Level Info -Message '可用的子文件夹：'

        for ($i = 0; $i -lt $subFolders.Count; $i++) {
            $folderPath = $subFolders[$i].FullName
            $folderImageCount = @(Get-ChildItem -LiteralPath $folderPath -File | Where-Object {
                    Test-SupportedImageFormat -File $PSItem -SupportedFormats $SupportedImageFormats
                }).Count
            Write-LogEntry -Level Info -Message "  [$($i + 1)] $($subFolders[$i].Name)/ (包含 $folderImageCount 张图片)"
        }

        [Nullable[int]]$folderChoice = Read-NumberInRange -Prompt "请选择无文字图文件夹 (1-$($subFolders.Count))" -Min 1 -Max $subFolders.Count
        if ($null -eq $folderChoice) {
            Write-LogEntry -Level Warning -Message '未读到输入（非交互环境），按跳过处理'
            return
        }

        $selectedFolder = $subFolders[$folderChoice - 1].FullName
        $nonTextImages = @(Get-ImageFile -Path $selectedFolder -SupportedFormats $SupportedImageFormats | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
        Write-LogEntry -Level Info -Message "已选择文件夹: $selectedFolder，包含 $($nonTextImages.Count) 张无文字图"
    }
    # 模式 3：输入自定义路径
    elseif ($choice -eq $options.Count - 1) {
        [string]$customPath = ''
        while (-not $customPath -or -not (Test-Path -LiteralPath $customPath)) {
            [string]$RawInput = Read-Host '请输入无文字图文件夹路径'
            # 非交互环境（stdin 已 EOF）下 Read-Host 恒返回 $null：按跳过处理，避免无限重问
            if ([string]::IsNullOrWhiteSpace($RawInput)) {
                Write-LogEntry -Level Warning -Message '未读到输入（非交互环境），按跳过处理'
                return
            }
            $customPath = $RawInput
            if (-not (Test-Path -LiteralPath $customPath)) {
                Write-LogEntry -Level Warning -Message "路径不存在: $customPath，请重新输入"
            }
        }

        $nonTextImages = @(Get-ImageFile -Path $customPath -SupportedFormats $SupportedImageFormats | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })
        Write-LogEntry -Level Info -Message "已选择自定义路径: $customPath，包含 $($nonTextImages.Count) 张无文字图"
    }
    # 模式 4：跳过
    else {
        Write-LogEntry -Level Info -Message '用户跳过无文字图处理'
        return
    }

    # 验证是否有图片
    if ($nonTextImages.Count -eq 0) {
        Write-LogEntry -Level Warning -Message '未找到任何无文字图'
        return
    }

    return $nonTextImages
}

