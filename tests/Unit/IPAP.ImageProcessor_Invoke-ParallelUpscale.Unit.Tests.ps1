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

        $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'

        Mock -ModuleName IPAP.ImageProcessor Write-InfoLog {}
        Mock -ModuleName IPAP.ImageProcessor Write-ErrorLog {}
        Mock -ModuleName IPAP.ImageProcessor Test-Path { return $true }
        Mock -ModuleName IPAP.ImageProcessor New-Item {}
        Mock -ModuleName IPAP.ImageProcessor ForEach-Object { return @{ Success = $true; Image = 'test.jpg' } }
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '参数验证 - Parameter Validation' {
        It '函数应有 Mandatory 参数 Images' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['Images']
            $param.Attributes.Mandatory | Should -Be $true
        }

        It '函数应有 Mandatory 参数 OutputDir' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['OutputDir']
            $param.Attributes.Mandatory | Should -Be $true
        }
    }

    Context '返回值结构测试' {
        It '应返回包含 SuccessCount 和 FailedCount 的哈希表' {
            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )

            $result = Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output'

            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'SuccessCount'
            $result.Keys | Should -Contain 'FailedCount'
        }
    }

    Context '边界值测试 - Boundary Value' {
        It '带空格的路径应处理' {
            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\Program Files\test1.jpg' }
            )

            $result = Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\Program Files\output'

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
