#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Invoke-ImageUpscale 验收测试
.DESCRIPTION
    验收测试 Invoke-ImageUpscale 函数在真实环境中的高清化处理能力。
    需要 realcugan-ncnn-vulkan.exe 存在于 bin 目录。
#>

Describe 'Invoke-ImageUpscale Acceptance Tests' -Tag 'Invoke-ImageUpscale', 'IPAP.ImageProcessor', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'
        $BinPath = Join-Path $ProjectRoot 'bin'
        $ExePath = Join-Path $BinPath 'realcugan-ncnn-vulkan.exe'
        $ImageDir = Join-Path $ProjectRoot 'tests\data\images'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.ImageProcessor module not found at: $ModulePath" -ForegroundColor Red
        }

        $Script:ExeExists = Test-Path $ExePath
        $Script:TestImagePath = Join-Path $ImageDir 'test_image_1.jpg'
        $Script:ImageExists = Test-Path $Script:TestImagePath
        $Script:OutputDir = Join-Path $env:TEMP "ipap_test_output_$(Get-Random)"

        if ($Script:ExeExists)
        {
            Initialize-ImageProcessor
        }
    }

    AfterAll {
        if (Test-Path $Script:OutputDir)
        {
            Remove-Item -Path $Script:OutputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '前置条件检查' {
        It 'realcugan-ncnn-vulkan.exe 应存在于 bin 目录' {
            if (-not $Script:ExeExists)
            {
                Set-ItResult -Skipped -Because 'realcugan-ncnn-vulkan.exe not found in bin directory'
                return
            }

            $Script:ExeExists | Should -Be $true
        }

        It '测试图片 test_image_1.jpg 应存在' {
            if (-not $Script:ImageExists)
            {
                Set-ItResult -Skipped -Because 'test_image_1.jpg not found'
                return
            }

            $Script:ImageExists | Should -Be $true
        }
    }

    Context '输出目录创建测试' {
        It '应能创建不存在的输出目录' {
            if (-not $Script:ExeExists -or -not $Script:ImageExists)
            {
                Set-ItResult -Skipped
                return
            }

            $uniqueOutputDir = Join-Path $env:TEMP "ipap_output_create_test_$(Get-Random)"

            try
            {
                $result = Invoke-ImageUpscale -ImagePath $Script:TestImagePath -OutputDir $uniqueOutputDir

                Test-Path $uniqueOutputDir | Should -Be $true
            }
            finally
            {
                if (Test-Path $uniqueOutputDir)
                {
                    Remove-Item -Path $uniqueOutputDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context '文件不存在测试' {
        It '源文件不存在时应返回 $false' {
            $nonExistentImage = Join-Path $env:TEMP "non_existent_$(Get-Random).jpg"

            $result = Invoke-ImageUpscale -ImagePath $nonExistentImage -OutputDir $Script:OutputDir

            $result | Should -Be $false
        }
    }
}
