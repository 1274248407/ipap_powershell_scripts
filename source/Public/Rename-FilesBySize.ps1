<#
.SYNOPSIS
    按文件大小排序并重命名目录中的文件
.DESCRIPTION
    将目录中的所有图片文件按文件大小从大到小排序，然后从指定起始编号开始连续重命名。
    重命名过程中保留原文件扩展名。
.PARAMETER Directory
    (string, Mandatory) 目标目录路径。
.PARAMETER StartIndex
    (int) 起始编号，默认为 1。
.EXAMPLE
    Rename-FilesBySize -Directory "C:\Images"
    将目录中的文件按大小从大到小排序，从 1 开始重命名。
.EXAMPLE
    Rename-FilesBySize -Directory "C:\Images" -StartIndex 10
    将目录中的文件按大小从大到小排序，从 10 开始重命名。
.INPUTS
    无
.OUTPUTS
    int (成功重命名的文件数量)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Rename-FilesBySize
{
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [ValidateRange(1, [int]::MaxValue)]
        [int]$StartIndex = 1
    )

    # 检查目录是否存在
    if (-not (Test-Path -LiteralPath $Directory))
    {
        # 记录错误现场后显式抛出强类型异常，中断本函数（Write-LogEntry 为纯日志函数）
        $ErrorMessage = "目录不存在: $Directory"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    # 获取目录中所有图片文件
    $files = @(Get-ImageFile -Path $Directory)

    if ($files.Count -eq 0)
    {
        Write-LogEntry -Level Info -Message "目录中没有图片文件: $Directory"
        return 0
    }

    # 按文件大小从大到小排序
    $sortedFiles = $files | Sort-Object -Property Length -Descending

    $renamedCount = 0
    $currentIndex = $StartIndex

    # 重命名文件
    foreach ($file in $sortedFiles)
    {
        $newName = "${currentIndex}$($file.Extension)"
        $newPath = Join-Path -Path $Directory -ChildPath $newName

        try
        {
            # 如果目标文件名已存在且不是当前文件，先删除
            if ((Test-Path -LiteralPath $newPath) -and ($newPath -ne $file.FullName))
            {
                Remove-Item -LiteralPath $newPath -Force
            }

            # 重命名文件
            if ($file.FullName -ne $newPath)
            {
                Rename-Item -LiteralPath $file.FullName -NewName $newName -Force
            }

            $renamedCount++
            $currentIndex++
        }
        catch
        {
            # 单个文件重命名失败不中断批次，降级为警告日志继续处理后续文件
            Write-LogEntry -Level Warning -Message "重命名文件失败: $($file.Name) -> $newName. 错误: $($PSItem.Exception.Message)"
        }
    }

    Write-LogEntry -Level Info -Message "已完成文件重命名: 成功 $renamedCount 个文件，从 $StartIndex 开始编号"

    return $renamedCount
}
