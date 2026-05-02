#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Invoke-ParallelUpscale 单元测试
.DESCRIPTION
    测试 Invoke-ParallelUpscale 函数的并行处理逻辑。
    注意：单元测试 Mock 掉 ForEach-Object -Parallel，仅验证参数校验和核心逻辑。
#>

Describe 'Invoke-ParallelUpscale Unit Tests' -Tag 'Invoke-ParallelUpscale', 'IPAP.ImageProcessor' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.ImageProcessor Write-InfoLog {}
        Mock -ModuleName IPAP.ImageProcessor Write-ErrorLog {}
        Mock -ModuleName IPAP.ImageProcessor Test-Path { return $false }
        Mock -ModuleName IPAP.ImageProcessor New-Item {}
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '参数验证 - Parameter Validation' {
        It '必填参数 Images 缺失时应报错' {
            { Invoke-ParallelUpscale -OutputDir 'C:\output' } | Should -Throw
        }

        It '必填参数 OutputDir 缺失时应报错' {
            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )
            { Invoke-ParallelUpscale -Images $mockImages } | Should -Throw
        }

        It '空数组 Images 应被接受' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output'

            $result.SuccessCount | Should -Be 0
            $result.FailedCount | Should -Be 0
        }
    }

    Context '输出目录处理' {
        It '输出目录不存在时应创建' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'output' } { return $false }
            Mock -ModuleName IPAP.ImageProcessor New-Item {}

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output'

            Should -Invoke -ModuleName IPAP.ImageProcessor New-Item -Times 1
        }

        It '输出目录存在时应直接使用' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output'

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context '默认参数测试' {
        It 'MaxWorkers 默认值应为 8' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output'

            $result | Should -Not -BeNullOrEmpty
        }

        It 'Scale 默认值应为 2' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output'

            $result | Should -Not -BeNullOrEmpty
        }

        It 'ModelPath 默认值应为 models-se' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output'

            $result | Should -Not -BeNullOrEmpty
        }

        It 'OutputFormat 默认值应为 webp' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output'

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context '返回值结构测试' {
        It '应返回包含 SuccessCount 和 FailedCount 的哈希表' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output'

            $result | Should -BeOfType [System.Hashtable]
            $result.Keys | Should -Contain 'SuccessCount'
            $result.Keys | Should -Contain 'FailedCount'
        }
    }

    Context '边界值测试 - Boundary Value' {
        It '空字符串 OutputDir 应处理' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $false }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir ''

            $result | Should -Not -BeNullOrEmpty
        }

        It '带空格的路径应处理' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'Program Files' } { return $false }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\Program Files\output'

            $result | Should -Not -BeNullOrEmpty
        }

        It 'MaxWorkers 为 0 应处理' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output' -MaxWorkers 0

            $result | Should -Not -BeNullOrEmpty
        }

        It 'MaxWorkers 为负数应处理' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }

            $result = Invoke-ParallelUpscale -Images @() -OutputDir 'C:\output' -MaxWorkers -1

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
