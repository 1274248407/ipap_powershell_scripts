<#
.SYNOPSIS
    分析图片目录并计算平均文件大小
.DESCRIPTION
    遍历指定目录中的图片文件，计算总大小和平均大小，并按自然顺序排序。
    若目录不存在则记录错误日志并抛出终止错误（由上层调用者捕获处理）。
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

function Get-ImageInfo {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceDir
    )

    Write-LogEntry -Level Info -Message "正在分析图片目录: $SourceDir"

    if (-not (Test-Path -LiteralPath $SourceDir)) {
        # 记录错误现场后显式抛出强类型异常，中断本函数（Write-LogEntry 为纯日志函数）
        $ErrorMessage = "源目录不存在: $SourceDir"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    [object[]]$Images = @()
    [long]$TotalSize = 0
    [int]$Count = 0

    Get-ChildItem -LiteralPath $SourceDir -File | ForEach-Object {
        if (Test-SupportedImageFormat -File $PSItem) {
            $Images += $PSItem
            $TotalSize += $PSItem.Length
            $Count++
        }
    }

    # @() 包裹管道结果，确保空管道时 $Images 仍为真正的空数组
    #（管道无输出会得到 AutomationNull 哨兵值，@() 对之不产生元素）
    $Images = @($Images | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name })

    [double]$AverageSize = $Count -gt 0 ? $TotalSize / 1024 / $Count : 0

    Write-LogEntry -Level Info -Message "发现 $Count 张图片，总大小: $([math]::Round($TotalSize / 1024 / 1024, 2)) MB，平均大小: $([math]::Round($AverageSize, 2)) KB"

    return @{
        Images      = $Images
        TotalSize   = $TotalSize
        AverageSize = $AverageSize
        Count       = $Count
    }
}

