#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Test-UpscaleResult 验收测试
.DESCRIPTION
    验收测试 Test-UpscaleResult 函数在真实环境中的结果验证能力。
#>

Describe 'Test-UpscaleResult Acceptance Tests' -Tag 'Test-UpscaleResult', 'IPAP.Workflow', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psm1'
        $CoreModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'

        if (Test-Path $CoreModulePath)
        {
            Import-Module $CoreModulePath -Force -Global
        }

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        $Script:TestOutputDir = Join-Path $env:TEMP "IPAP_Test_$(Get-Random)"
        New-Item -ItemType Directory -Path $Script:TestOutputDir -Force | Out-Null
    }

    AfterAll {
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
        Remove-Item -Path $Script:TestOutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context '正常处理结果 - Normal Processing Results' {
        It '所有图片处理成功时应返回 $true' {
            for ($i = 1; $i -le 3; $i++)
            {
                $null = New-Item -Path (Join-Path $Script:TestOutputDir "test_$i.jpg") -ItemType File -Force
            }

            $result = Test-UpscaleResult -ExpectedCount 3 -OutputDir $Script:TestOutputDir

            $result | Should -Be $true
        }

        It '部分成功时应返回 $false' {
            for ($i = 1; $i -le 2; $i++)
            {
                $null = New-Item -Path (Join-Path $Script:TestOutputDir "test_$i.png") -ItemType File -Force
            }

            $result = Test-UpscaleResult -ExpectedCount 5 -OutputDir $Script:TestOutputDir

            $result | Should -Be $false
        }

        It '全部失败时应返回 $false' {
            $result = Test-UpscaleResult -ExpectedCount 3 -OutputDir $Script:TestOutputDir

            $result | Should -Be $false
        }
    }

    Context '边界条件测试 - Boundary Conditions' {
        It 'ExpectedCount 为 0 时应返回 $false' {
            $null = New-Item -Path (Join-Path $Script:TestOutputDir "single.jpg") -ItemType File -Force

            $result = Test-UpscaleResult -ExpectedCount 0 -OutputDir $Script:TestOutputDir

            $result | Should -Be $false
        }

        It '输出目录为空时应返回 $false' {
            $result = Test-UpscaleResult -ExpectedCount 3 -OutputDir $Script:TestOutputDir

            $result | Should -Be $false
        }
    }

    Context 'ProcessResult 参数测试 - ProcessResult Parameter' {
        It '提供 ProcessResult 时应正确对比' {
            $null = New-Item -Path (Join-Path $Script:TestOutputDir "image1.webp") -ItemType File -Force
            $null = New-Item -Path (Join-Path $Script:TestOutputDir "image2.webp") -ItemType File -Force

            $processResult = @{ SuccessCount = 2; FailedCount = 0 }
            $result = Test-UpscaleResult -ExpectedCount 2 -OutputDir $Script:TestOutputDir -ProcessResult $processResult

            $result | Should -Be $true
        }

        It 'ProcessResult 与实际不一致时应检测到差异' {
            $null = New-Item -Path (Join-Path $Script:TestOutputDir "actual.jpg") -ItemType File -Force

            $processResult = @{ SuccessCount = 5; FailedCount = 0 }
            $result = Test-UpscaleResult -ExpectedCount 5 -OutputDir $Script:TestOutputDir -ProcessResult $processResult

            $result | Should -Be $false
        }
    }

    Context '文件类型过滤测试 - File Type Filtering' {
        It '应只统计支持的图片格式' {
            $null = New-Item -Path (Join-Path $Script:TestOutputDir "valid.jpg") -ItemType File -Force
            $null = New-Item -Path (Join-Path $Script:TestOutputDir "valid.png") -ItemType File -Force
            $null = New-Item -Path (Join-Path $Script:TestOutputDir "invalid.txt") -ItemType File -Force
            $null = New-Item -Path (Join-Path $Script:TestOutputDir "invalid.pdf") -ItemType File -Force

            $result = Test-UpscaleResult -ExpectedCount 2 -OutputDir $Script:TestOutputDir

            $result | Should -Be $true
        }
    }

    Context '目录不存在测试 - Directory Not Found' {
        It 'OutputDir 不存在时应抛出异常' {
            $nonexistentDir = Join-Path $env:TEMP "nonexistent_$(Get-Random)"

            { Test-UpscaleResult -ExpectedCount 3 -OutputDir $nonexistentDir } | Should -Throw
        }
    }
}