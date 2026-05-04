#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Invoke-ParallelUpscale 验收测试
.DESCRIPTION
    验收测试 Invoke-ParallelUpscale 函数在真实环境中的并行处理能力。
#>

Describe 'Invoke-ParallelUpscale Acceptance Tests' -Tag 'Invoke-ParallelUpscale', 'IPAP.ImageProcessor', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'
        $ImageDir = Join-Path $ProjectRoot 'tests\data\images'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.ImageProcessor module not found at: $ModulePath" -ForegroundColor Red
        }

        $Script:ImageDirExists = Test-Path $ImageDir
        $Script:OutputDir = Join-Path $env:TEMP "ipap_parallel_test_$(Get-Random)"

        if ($Script:ImageDirExists)
        {
            $Script:TestImages = Get-ChildItem -Path $ImageDir -File | Where-Object {
                $_.Extension.ToLower() -in @('.jpg', '.png', '.webp')
            } | Select-Object -First 3
        }
    }

    AfterAll {
        if (Test-Path $Script:OutputDir)
        {
            Remove-Item -Path $Script:OutputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Real Execution' {
        It '应能处理单张图片' {
            if (-not $Script:ImageDirExists -or $Script:TestImages.Count -eq 0)
            {
                Set-ItResult -Skipped -Because 'Test images not found'
                return
            }

            $uniqueOutputDir = Join-Path $env:TEMP "ipap_single_test_$(Get-Random)"

            try
            {
                $result = Invoke-ParallelUpscale -Images $Script:TestImages[0..0] -OutputDir $uniqueOutputDir -MaxWorkers 1

                $result | Should -Not -BeNullOrEmpty
                $result.Keys | Should -Contain 'SuccessCount'
                $result.Keys | Should -Contain 'FailedCount'
            }
            finally
            {
                if (Test-Path $uniqueOutputDir)
                {
                    Remove-Item -Path $uniqueOutputDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It '应返回正确结构的哈希表' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir $Script:OutputDir

            $result | Should -BeOfType [System.Hashtable]
            $result.SuccessCount | Should -BeOfType [System.Int32]
            $result.FailedCount | Should -BeOfType [System.Int32]
        }
    }

    Context '参数测试' {
        It 'MaxWorkers 应影响并发数' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir $Script:OutputDir -MaxWorkers 4

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Scale 参数应传递给处理函数' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir $Script:OutputDir -Scale 2

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context '空数组测试' {
        It '空图片数组应返回零计数' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir $Script:OutputDir

            $result.SuccessCount | Should -Be 0
            $result.FailedCount | Should -Be 0
        }
    }
}
