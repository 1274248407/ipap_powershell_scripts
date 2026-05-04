<#
.SYNOPSIS
    IPAP 工作流图片处理模块
.DESCRIPTION
    提供图片分析、高清化处理和并行处理功能。
#>

# ImageProcessor 模块依赖 IPAP.Core，IPAP.Core 由 Main.ps1 统一导入
# 不需要重复导入 PoShLog 和 IPAP.Core

Export-ModuleMember

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
    Website: `https://github.com/1274248407`
#>
function Get-ImageInfo
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceDir
    )

    Write-InfoLog "Analyzing image directory: $SourceDir"

    if (-not (Test-Path -LiteralPath $SourceDir))
    {
        Write-ErrorLog "Source directory not found: $SourceDir"
        return @{ Images = @(); TotalSize = 0; AverageSize = 0; Count = 0 }
    }

    $images = @()
    $totalSize = 0
    $count = 0

    Get-ChildItem -LiteralPath $SourceDir -File | ForEach-Object {
        if ($Global:SupportedImageFormats -contains $PSItem.Extension.ToLower())
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

    Write-InfoLog "Found $count images, total size: $([math]::Round($totalSize / 1024 / 1024, 2)) MB, average size: $([math]::Round($averageSize, 2)) KB"

    return @{
        Images      = $images
        TotalSize   = $totalSize
        AverageSize = $averageSize
        Count       = $count
    }
}

<#
.SYNOPSIS
    判断是否需要高清化处理
.DESCRIPTION
    根据平均文件大小判断是否需要进行图片高清化处理，阈值为 1000KB。
.PARAMETER AverageSize
    (double, Mandatory) 平均文件大小（KB）。
    （适用于所有参数集）
.EXAMPLE
    Test-NeedUpscale -AverageSize 500
    平均文件大小小于 1000KB，返回 $true。
.EXAMPLE
    Test-NeedUpscale -AverageSize 1500
    平均文件大小大于等于 1000KB，返回 $false。
.INPUTS
    double
.OUTPUTS
    bool
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Test-NeedUpscale
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [double]$AverageSize
    )

    $threshold = 1000

    if ($AverageSize -lt $threshold)
    {
        Write-InfoLog "Average file size $([math]::Round($AverageSize, 2)) KB < $threshold KB, upscaling needed"
        return $true
    }
    else
    {
        Write-InfoLog "Average file size $([math]::Round($AverageSize, 2)) KB >= $threshold KB, skipping upscaling"
        return $false
    }
}

<#
.SYNOPSIS
    对单张图片进行高清化处理
.DESCRIPTION
    使用 realcugan-ncnn-vulkan 对单张图片进行高清化处理，支持指定缩放比例、噪声级别和输出格式。
    若可执行文件不存在或输入文件不存在则记录错误日志并返回 $false。
.PARAMETER ImagePath
    (string, Mandatory) 源图片路径。
    （适用于所有参数集）
.PARAMETER OutputDir
    (string, Mandatory) 输出目录。
    （适用于所有参数集）
.PARAMETER Scale
    (int) 缩放比例，默认为 2。
    （适用于所有参数集）
.PARAMETER NoiseLevel
    (int) 噪声级别，默认为 0。
    （适用于所有参数集）
.PARAMETER ModelPath
    (string) 模型路径，默认为 "models-se"。
    （适用于所有参数集）
.PARAMETER OutputFormat
    (string) 输出格式，默认为 "webp"。
    （适用于所有参数集）
.EXAMPLE
    Invoke-ImageUpscale -ImagePath "input.jpg" -OutputDir "output"
    对 input.jpg 进行高清化处理。
.INPUTS
    无
.OUTPUTS
    bool
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Invoke-ImageUpscale
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [int]$Scale = 2,
        [int]$NoiseLevel = 0,
        [string]$ModelPath = 'models-se',
        [string]$OutputFormat = 'webp'
    )

    if (-not $Global:RealCuganExePath)
    {
        Write-ErrorLog 'realcugan-ncnn-vulkan.exe not found, cannot perform upscaling'
        return $false
    }

    if (-not (Test-Path -LiteralPath $ImagePath))
    {
        Write-ErrorLog "Input file not found: $ImagePath"
        return $false
    }

    if (-not (Test-Path -LiteralPath $OutputDir))
    {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    try
    {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($ImagePath)
        $outputPath = Join-Path $OutputDir "${fileName}.${OutputFormat}"

        $realCuganArgs = @(
            '-i', $ImagePath,
            '-o', $outputPath,
            '-n', $NoiseLevel,
            '-s', $Scale,
            '-t', '128',
            '-m', $ModelPath,
            '-f', $OutputFormat
        )

        & $Global:RealCuganExePath @realCuganArgs

        if (Test-Path -LiteralPath $outputPath)
        {
            return $true
        }
        else
        {
            return $false
        }
    }
    catch
    {
        return $false
    }
}

<#
.SYNOPSIS
    并行使用 realcugan-ncnn-vulkan 高清化处理图片
.DESCRIPTION
    使用 PowerShell 的并行处理功能同时高清化多张图片，提高处理效率。
    返回处理结果统计（成功数和失败数）。
.PARAMETER Images
    (array, Mandatory) 图片文件对象数组。
    （适用于所有参数集）
.PARAMETER OutputDir
    (string, Mandatory) 输出目录。
    （适用于所有参数集）
.PARAMETER MaxWorkers
    (int) 最大并发数，默认为 8。
    （适用于所有参数集）
.PARAMETER Scale
    (int) 缩放比例，默认为 2。
    （适用于所有参数集）
.PARAMETER ModelPath
    (string) 模型路径，默认为 "models-se"。
    （适用于所有参数集）
.PARAMETER OutputFormat
    (string) 输出格式，默认为 "webp"。
    （适用于所有参数集）
.EXAMPLE
    Invoke-ParallelUpscale -Images $images -OutputDir "output" -MaxWorkers 4
    使用 4 个并发处理图片。
.INPUTS
    无
.OUTPUTS
    hashtable (包含 SuccessCount, FailedCount)
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Invoke-ParallelUpscale
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Images,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [int]$MaxWorkers = 8,
        [int]$Scale = 2,
        [string]$ModelPath = 'models-se',
        [string]$OutputFormat = 'webp'
    )

    Write-InfoLog "Starting parallel image processing, concurrency: $MaxWorkers"

    if (-not (Test-Path -LiteralPath $OutputDir))
    {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $successCount = 0
    $failedCount = 0

    $Images | ForEach-Object -Parallel {
        $image = $PSItem
        $outputDir = $using:OutputDir
        $scale = $using:Scale
        $modelPath = $using:ModelPath
        $outputFormat = $using:OutputFormat
        $realCuganExePath = $using:Global:RealCuganExePath

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($image.FullName)
        $outputPath = Join-Path $outputDir "${fileName}.${outputFormat}"

        try
        {
            $realCuganArgs = @(
                '-i', $image.FullName,
                '-o', $outputPath,
                '-n', 0,
                '-s', $scale,
                '-t', '128',
                '-m', $modelPath,
                '-f', $outputFormat
            )

            & $realCuganExePath @realCuganArgs

            if (Test-Path -LiteralPath $outputPath)
            {
                return @{ Success = $true; Image = $image.Name }
            }
            else
            {
                return @{ Success = $false; Image = $image.Name }
            }
        }
        catch
        {
            return @{ Success = $false; Image = $image.Name; Error = $PSItem.Exception.Message }
        }
    } -ThrottleLimit $MaxWorkers | ForEach-Object {
        if ($PSItem.Success)
        {
            Write-InfoLog "Image processed successfully: $($PSItem.Image)"
            $successCount++
        }
        else
        {
            Write-ErrorLog "Image processing failed: $($PSItem.Image)"
            $failedCount++
        }
    }

    Write-InfoLog "Parallel processing completed, success: $successCount, failed: $failedCount"

    return @{ SuccessCount = $successCount; FailedCount = $failedCount }
}

<#
.SYNOPSIS
    初始化图片处理模块
.DESCRIPTION
    定位 realcugan-ncnn-vulkan.exe，为后续高清化处理做准备。
    若无法定位可执行文件则记录警告日志。
.EXAMPLE
    Initialize-ImageProcessor
    初始化图片处理模块。
.INPUTS
    无
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
    Website: `https://github.com/1274248407`
#>
function Initialize-ImageProcessor
{
    [CmdletBinding()]
    param ()

    $Global:RealCuganExePath = Get-RealCuganExePath
    if (-not $Global:RealCuganExePath)
    {
        Write-WarningLog 'Cannot locate realcugan-ncnn-vulkan.exe, upscaling functionality will be unavailable'
    }
}

Export-ModuleMember -Function @(
    'Get-ImageInfo',
    'Test-NeedUpscale',
    'Invoke-ImageUpscale',
    'Invoke-ParallelUpscale',
    'Initialize-ImageProcessor'
)
