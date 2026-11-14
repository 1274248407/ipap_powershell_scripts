<#
.SYNOPSIS
    验证高清化处理结果
.DESCRIPTION
    检查输出目录中的图片数量是否与预期相符，并校验图片扩展名是否统一为期望格式。
    数量对但格式不对（例如转码失败回退复制了原图）会被判为失败，
    避免「数量对了、格式不对」的假通过。
.PARAMETER ExpectedCount
    (int, Mandatory) 预期输出图片数量，必须大于 0。
.PARAMETER OutputDir
    (string) 输出目录路径。
.PARAMETER OutputFormat
    (string) 期望的图片扩展名（jpg/png/webp），默认为 webp。
.EXAMPLE
    Test-UpscaleResult -ExpectedCount 10 -OutputDir "C:\Output"
.EXAMPLE
    Test-UpscaleResult -ExpectedCount 10 -OutputDir "C:\Output" -OutputFormat 'webp'
.INPUTS
    无
.OUTPUTS
    bool
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Test-UpscaleResult {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [int]$ExpectedCount,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [ValidateSet('jpg', 'png', 'webp')]
        [string]$OutputFormat = 'webp'
    )

    # 参数契约：ExpectedCount 必须为正数（生产调用点只在 > 0 时调用本函数）
    if ($ExpectedCount -lt 1) {
        $ErrorMessage = "ExpectedCount 必须大于 0（当前值: $ExpectedCount）"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage, 'ExpectedCount')
    }

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        # 记录错误现场后显式抛出强类型异常，中断本函数（Write-LogEntry 为纯日志函数）
        $ErrorMessage = "输出目录不存在: $OutputDir"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.IO.DirectoryNotFoundException]::new($ErrorMessage)
    }

    $outputFiles = Get-ChildItem -LiteralPath $OutputDir -File | Where-Object {
        Test-SupportedImageFormat -File $PSItem
    }

    $actualCount = $outputFiles.Count

    if ($actualCount -eq 0) {
        # 记录错误现场后显式抛出强类型异常，中断本函数（Write-LogEntry 为纯日志函数）
        $ErrorMessage = '并行处理完全失败，未生成任何输出文件'
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.InvalidOperationException]::new($ErrorMessage)
    }

    $successRate = [math]::Round(($actualCount / $ExpectedCount) * 100, 1)

    if ($actualCount -ne $ExpectedCount) {
        $failedCount = $ExpectedCount - $actualCount
        Write-LogEntry -Level Warning -Message "并行处理部分完成 - 预期: $ExpectedCount, 实际: $actualCount, 失败: $failedCount ($successRate%)"
        return $false
    }

    # 格式校验：转码失败会回退复制原图，数量能对上但扩展名不是 webp
    [string[]]$wrongFormatFiles = @(
        $outputFiles |
            Where-Object { $PSItem.Extension -ne ".$OutputFormat" } |
            ForEach-Object { $PSItem.Name }
    )
    if ($wrongFormatFiles.Count -gt 0) {
        Write-LogEntry -Level Warning -Message "输出格式不符合预期（期望 .$OutputFormat，实际含: $($wrongFormatFiles -join ', ')）"
        return $false
    }

    Write-LogEntry -Level Info -Message "高清化处理成功完成。预期: $ExpectedCount, 实际: $actualCount (100%)"
    return $true
}
