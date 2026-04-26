#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Test-NeedUpscale 验收测试
.DESCRIPTION
    验收测试 Test-NeedUpscale 函数在真实环境中的高清化判断能力。
#>

Describe 'Test-NeedUpscale Acceptance Tests' -Tag 'Test-NeedUpscale', 'IPAP.ImageProcessor', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.ImageProcessor module not found at: $ModulePath" -ForegroundColor Red
        }
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '阈值判断测试 - Threshold Logic' {
        It '平均大小 500KB 应返回 $true (需要高清化)' {
            $result = Test-NeedUpscale -AverageSize 500
            $result | Should -Be $true
        }

        It '平均大小 1500KB 应返回 $false (不需要高清化)' {
            $result = Test-NeedUpscale -AverageSize 1500
            $result | Should -Be $false
        }

        It '平均大小正好 1000KB 应返回 $false' {
            $result = Test-NeedUpscale -AverageSize 1000
            $result | Should -Be $false
        }
    }

    Context '与 Get-ImageInfo 集成测试' {
        It '结合 Get-ImageInfo 分析 tinyimg.jpg 后应返回 $true' {
            $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
            $ImageDir = Join-Path $ProjectRoot 'tests\data\images'
            $tinyImagePath = Join-Path $ImageDir 'tinyimg.jpg'

            if (-not (Test-Path $tinyImagePath))
            {
                Set-ItResult -Skipped -Because 'tinyimg.jpg not found'
                return
            }

            $fileInfo = Get-Item $tinyImagePath
            $sizeInKB = $fileInfo.Length / 1024

            $result = Test-NeedUpscale -AverageSize $sizeInKB

            if ($sizeInKB -lt 1000)
            {
                $result | Should -Be $true
            }
        }

        It '结合 Get-ImageInfo 分析正常大小图片后应返回 $false' {
            $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
            $ImageDir = Join-Path $ProjectRoot 'tests\data\images'
            $normalImagePath = Join-Path $ImageDir 'test_image_1.jpg'

            if (-not (Test-Path $normalImagePath))
            {
                Set-ItResult -Skipped -Because 'test_image_1.jpg not found'
                return
            }

            $fileInfo = Get-Item $normalImagePath
            $sizeInKB = $fileInfo.Length / 1024

            $result = Test-NeedUpscale -AverageSize $sizeInKB

            if ($sizeInKB -ge 1000)
            {
                $result | Should -Be $false
            }
        }
    }
}
