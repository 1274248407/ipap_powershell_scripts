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

