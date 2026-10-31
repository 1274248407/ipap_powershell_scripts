<#
.SYNOPSIS
    分析图片质量分级
.DESCRIPTION
    通过 FFprobe 获取图片分辨率，并通过 FFmpeg 去网点提取高频细节 YDIF 值。
    根据分辨率和 YDIF 值将图片分为三个级别：Level 0（高清跳过）、Level 1（轻度模糊，FFmpeg 锐化）、Level 2（重度模糊，Real-CUGAN AI 超分）。
.PARAMETER Images
    (array, Mandatory) 图片文件对象数组，每个对象需要包含 FullName 属性。
    （适用于所有参数集）
.EXAMPLE
    Get-ImageLevel -Images $images
    分析图片数组的质量分级。
.INPUTS
    array
.OUTPUTS
    PSCustomObject (每个对象包含 Index, Image, Level, LongEdge, YDIF 属性，逐个输出)
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-ImageLevel {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Images
    )

    # 获取 FFprobe 和 FFmpeg 路径（从配置读取，fallback 到 PATH；缺失时内部直接抛出终止错误）
    $FfprobePath = Get-FfprobePath
    $FfmpegPath = Get-FfmpegPath

    Write-LogEntry -Level Info -Message "开始分析 $($Images.Count) 张图片的质量分级..."

    # 并行分析所有图片（保留原始顺序）
    $indexedImages = for ($i = 0; $i -lt $Images.Count; $i++) {
        [PSCustomObject]@{ Index = $i; Image = $Images[$i] }
    }

    # 并行 runspace 不继承模块函数，因此把单图分析函数序列化后注入；
    # 单图逻辑集中在 Get-ImageLevelForImage，便于直接做 L1-L5 单测
    $WorkerSource = ${function:Get-ImageLevelForImage}.ToString()
    $results = $indexedImages | ForEach-Object -Parallel {
        $worker = [scriptblock]::Create($using:WorkerSource)
        & $worker -Index $PSItem.Index -Image $PSItem.Image `
            -FfprobePath $using:FfprobePath -FfmpegPath $using:FfmpegPath
    } -ThrottleLimit 8

    # 按原始索引排序恢复顺序
    $results = $results | Sort-Object -Property Index

    Write-LogEntry -Level Info -Message "图片分级分析完成: $($results.Count) 张"

    $level0Count = @($results | Where-Object { $PSItem.Level -eq 0 }).Count
    $level1Count = @($results | Where-Object { $PSItem.Level -eq 1 }).Count
    $level2Count = @($results | Where-Object { $PSItem.Level -eq 2 }).Count
    Write-LogEntry -Level Info -Message "分级结果 - Level 0 (高清跳过): $level0Count, Level 1 (FFmpeg): $level1Count, Level 2 (Real-CUGAN): $level2Count"

    return $results
}
