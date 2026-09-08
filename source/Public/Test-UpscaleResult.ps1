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
    }
    else
    {
        $failedCount = $ExpectedCount - $actualCount
        Write-WarningLog "并行处理部分完成 - 预期: $ExpectedCount, 实际: $actualCount, 失败: $failedCount ($successRate%)"
        return $false
    }
}

