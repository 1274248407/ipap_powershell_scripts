<#
.SYNOPSIS
    IPAP 工作流图片处理模块
.DESCRIPTION
    提供图片分析、高清化处理和并行处理功能。
#>

Import-Module "$PSScriptRoot\..\IPAP.Core\IPAP.Core.psm1" -Force

$Global:RealCuganExePath = $null

Export-ModuleMember -Variable @("RealCuganExePath")

<#
.SYNOPSIS
    分析图片目录并计算平均文件大小
.DESCRIPTION
    遍历指定目录中的图片文件，计算总大小和平均大小，并按自然顺序排序。
.PARAMETER SourceDir
    源图片目录路径。
.EXAMPLE
    Get-ImageInfo -SourceDir "C:\Images"
    分析 C:\Images 目录中的图片文件。
#>
function Get-ImageInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceDir
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Analyzing image directory: $SourceDir" -ForegroundColor Cyan

    if (-not (Test-Path $SourceDir)) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] Source directory not found: $SourceDir" -ForegroundColor Red
        return @{ Images = @(); TotalSize = 0; AverageSize = 0; Count = 0 }
    }

    $images = @()
    $totalSize = 0
    $count = 0

    Get-ChildItem -Path $SourceDir -File | ForEach-Object {
        if ($Global:SupportedImageFormats -contains $_.Extension.ToLower()) {
            $images += $_
            $totalSize += $_.Length
            $count++
        }
    }

    $images = $images | Sort-Object -Property { Get-NaturalSortKey $_.Name }

    $averageSize = 0
    if ($count -gt 0) {
        $averageSize = $totalSize / 1024 / $count
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Found $count images, total size: $([math]::Round($totalSize / 1024 / 1024, 2)) MB, average size: $([math]::Round($averageSize, 2)) KB" -ForegroundColor Cyan

    return @{
        Images = $images
        TotalSize = $totalSize
        AverageSize = $averageSize
        Count = $count
    }
}

<#
.SYNOPSIS
    判断是否需要高清化处理
.DESCRIPTION
    根据平均文件大小判断是否需要进行图片高清化处理，阈值为 1000KB。
.PARAMETER AverageSize
    平均文件大小（KB）。
.EXAMPLE
    Test-NeedUpscale -AverageSize 500
    平均文件大小小于 1000KB，返回 $true。
#>
function Test-NeedUpscale {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [double]$AverageSize
    )

    $threshold = 1000

    if ($AverageSize -lt $threshold) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [INFO] Average file size $([math]::Round($AverageSize, 2)) KB < $threshold KB, upscaling needed" -ForegroundColor Cyan
        return $true
    } else {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [INFO] Average file size $([math]::Round($AverageSize, 2)) KB >= $threshold KB, skipping upscaling" -ForegroundColor Cyan
        return $false
    }
}

<#
.SYNOPSIS
    对单张图片进行高清化处理
.DESCRIPTION
    使用 realcugan-ncnn-vulkan 对单张图片进行高清化处理，支持指定缩放比例、噪声级别和输出格式。
.PARAMETER ImagePath
    源图片路径。
.PARAMETER OutputDir
    输出目录。
.PARAMETER Scale
    缩放比例，默认为 2。
.PARAMETER NoiseLevel
    噪声级别，默认为 0。
.PARAMETER ModelPath
    模型路径，默认为 "models-se"。
.PARAMETER OutputFormat
    输出格式，默认为 "webp"。
.EXAMPLE
    Invoke-ImageUpscale -ImagePath "input.jpg" -OutputDir "output"
    对 input.jpg 进行高清化处理。
#>
function Invoke-ImageUpscale {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [int]$Scale = 2,
        [int]$NoiseLevel = 0,
        [string]$ModelPath = "models-se",
        [string]$OutputFormat = "webp"
    )

    if (-not $Global:RealCuganExePath) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] realcugan-ncnn-vulkan.exe not found, cannot perform upscaling" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $ImagePath)) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] Input file not found: $ImagePath" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    try {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($ImagePath)
        $outputPath = Join-Path $OutputDir "${fileName}.${OutputFormat}"

        $args = @(
            "-i", $ImagePath,
            "-o", $outputPath,
            "-n", $NoiseLevel,
            "-s", $Scale,
            "-t", "128",
            "-m", $ModelPath,
            "-f", $OutputFormat
        )

        & $Global:RealCuganExePath @args

        if (Test-Path $outputPath) {
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

<#
.SYNOPSIS
    并行处理图片
.DESCRIPTION
    使用 PowerShell 的并行处理功能同时处理多张图片，提高处理效率。
.PARAMETER Images
    图片文件对象数组。
.PARAMETER OutputDir
    输出目录。
.PARAMETER MaxWorkers
    最大并发数，默认为 8。
.PARAMETER Scale
    缩放比例，默认为 2。
.PARAMETER ModelPath
    模型路径，默认为 "models-se"。
.PARAMETER OutputFormat
    输出格式，默认为 "webp"。
.EXAMPLE
    Invoke-ParallelUpscale -Images $images -OutputDir "output" -MaxWorkers 4
    使用 4 个并发处理图片。
#>
function Invoke-ParallelUpscale {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Images,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [int]$MaxWorkers = 8,
        [int]$Scale = 2,
        [string]$ModelPath = "models-se",
        [string]$OutputFormat = "webp"
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Starting parallel image processing, concurrency: $MaxWorkers" -ForegroundColor Cyan

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    $successCount = 0
    $failedCount = 0

    $Images | ForEach-Object -Parallel {
        $image = $_
        $outputDir = $using:OutputDir
        $scale = $using:Scale
        $modelPath = $using:ModelPath
        $outputFormat = $using:OutputFormat
        $realCuganExePath = $using:Global:RealCuganExePath

        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($image.FullName)
        $outputPath = Join-Path $outputDir "${fileName}.${outputFormat}"

        try {
            $args = @(
                "-i", $image.FullName,
                "-o", $outputPath,
                "-n", 0,
                "-s", $scale,
                "-t", "128",
                "-m", $modelPath,
                "-f", $outputFormat
            )

            & $realCuganExePath @args

            if (Test-Path $outputPath) {
                return @{ Success = $true; Image = $image.Name }
            } else {
                return @{ Success = $false; Image = $image.Name }
            }
        } catch {
            return @{ Success = $false; Image = $image.Name; Error = $_.Exception.Message }
        }
    } -ThrottleLimit $MaxWorkers | ForEach-Object {
        if ($_.Success) {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$timestamp] [SUCCESS] Image processed successfully: $($_.Image)" -ForegroundColor Green
            $successCount++
        } else {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$timestamp] [ERROR] Image processing failed: $($_.Image)" -ForegroundColor Red
            $failedCount++
        }
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] Parallel processing completed, success: $successCount, failed: $failedCount" -ForegroundColor Cyan

    return @{ SuccessCount = $successCount; FailedCount = $failedCount }
}

<#
.SYNOPSIS
    初始化图片处理模块
.DESCRIPTION
    定位 realcugan-ncnn-vulkan.exe，为后续高清化处理做准备。
.EXAMPLE
    Initialize-ImageProcessor
    初始化图片处理模块。
#>
function Initialize-ImageProcessor {
    [CmdletBinding()]
    param ()

    $Global:RealCuganExePath = Get-RealCuganExePath
    if (-not $Global:RealCuganExePath) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [WARNING] Cannot locate realcugan-ncnn-vulkan.exe, upscaling functionality will be unavailable" -ForegroundColor Yellow
    }
}

Export-ModuleMember -Function @(
    "Get-ImageInfo",
    "Test-NeedUpscale",
    "Invoke-ImageUpscale",
    "Invoke-ParallelUpscale",
    "Initialize-ImageProcessor"
)
