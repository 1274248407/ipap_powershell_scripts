<#
.SYNOPSIS
    分析图片目录并计算平均文件大小
.DESCRIPTION
    遍历指定目录中的图片文件，计算总大小和平均大小，并按自然顺序排序。
    若目录不存在则记录错误日志并返回空结果。
.PARAMETER SourceDir
    (string, Mandatory) 源图片目录路径。
    （适用于所有参数集）
.EXAMPLE
    Get-ImageInfo -SourceDir "C:\Images"
    分析 C:\Images 目录中的图片文件。
.INPUTS
    无
.OUTPUTS
    hashtable (包含 Images, TotalSize, AverageSize, Count)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-ImageInfo
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceDir
    )

    Write-InfoLog "正在分析图片目录: $SourceDir"

    if (-not (Test-Path -LiteralPath $SourceDir))
    {
        Write-ErrorLog "源目录不存在: $SourceDir"
    }

    $images = @()
    $totalSize = 0
    $count = 0

    Get-ChildItem -LiteralPath $SourceDir -File | ForEach-Object {
        if (Test-SupportedImageFormat -File $PSItem)
        {
            $images += $PSItem
            $totalSize += $PSItem.Length
            $count++
        }
    }

    $images = $images | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name }

    $averageSize = 0
    if ($count -gt 0)
    {
        $averageSize = $totalSize / 1024 / $count
    }

    Write-InfoLog "发现 $count 张图片，总大小: $([math]::Round($totalSize / 1024 / 1024, 2)) MB，平均大小: $([math]::Round($averageSize, 2)) KB"

    return @{
        Images      = $images
        TotalSize   = $totalSize
        AverageSize = $averageSize
        Count       = $count
    }
}

