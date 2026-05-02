#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Invoke-ImageUpscale 单元测试
.DESCRIPTION
    测试 Invoke-ImageUpscale 函数的高清化处理逻辑。
    注意：单元测试完全 Mock 掉外部 exe 调用和文件系统操作。
#>

Describe 'Invoke-ImageUpscale Unit Tests' -Tag 'Invoke-ImageUpscale', 'IPAP.ImageProcessor' {
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
        Mock -ModuleName IPAP.ImageProcessor Get-ChildItem {}
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context 'RealCuganExePath 缺失处理' {
        It 'exe 路径未设置时应返回 $false' {
            $Global:RealCuganExePath = $null

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output'

            $result | Should -Be $false
        }

        It 'exe 路径为空时应返回 $false' {
            $Global:RealCuganExePath = ''

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output'

            $result | Should -Be $false
        }
    }

    Context '输入文件验证 - Input Validation' {
        BeforeEach {
            $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
        }

        It '源文件不存在时应返回 $false' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'test\.jpg' } { return $false }

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output'

            $result | Should -Be $false
        }
    }

    Context '输出目录处理' {
        BeforeEach {
            $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
        }

        It '输出目录不存在时应创建' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'test\.jpg' } { return $true }
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'output' } { return $false }
            Mock -ModuleName IPAP.ImageProcessor New-Item {}

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output'

            Should -Invoke -ModuleName IPAP.ImageProcessor New-Item -Times 1
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        BeforeEach {
            $Global:RealCuganExePath = $null
        }

        It '必填参数 ImagePath 缺失时应报错' {
            { Invoke-ImageUpscale -OutputDir 'C:\output' } | Should -Throw
        }

        It '必填参数 OutputDir 缺失时应报错' {
            { Invoke-ImageUpscale -ImagePath 'C:\test.jpg' } | Should -Throw
        }

        It '应使用默认参数值' {
            $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'test\.jpg' } { return $true }
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'output' } { return $true }
            Mock -ModuleName IPAP.ImageProcessor Get-ChildItem {}

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output'

            $result | Should -Be $false
        }

        It 'Scale 参数应接受有效值' {
            $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'test\.jpg' } { return $true }
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'output' } { return $true }

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output' -Scale 4

            $result | Should -Be $false
        }

        It 'NoiseLevel 参数应接受有效值' {
            $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'test\.jpg' } { return $true }
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'output' } { return $true }

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output' -NoiseLevel 3

            $result | Should -Be $false
        }

        It 'ModelPath 参数应接受有效值' {
            $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'test\.jpg' } { return $true }
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'output' } { return $true }

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output' -ModelPath 'models-pro'

            $result | Should -Be $false
        }

        It 'OutputFormat 参数应接受有效值' {
            $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'test\.jpg' } { return $true }
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'output' } { return $true }

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir 'C:\output' -OutputFormat 'png'

            $result | Should -Be $false
        }
    }

    Context '边界值测试 - Boundary Value' {
        BeforeEach {
            $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
        }

        It '空字符串 ImagePath 应处理' {
            $result = Invoke-ImageUpscale -ImagePath '' -OutputDir 'C:\output'

            $result | Should -Be $false
        }

        It '空字符串 OutputDir 应处理' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path { return $false }

            $result = Invoke-ImageUpscale -ImagePath 'C:\test.jpg' -OutputDir ''

            $result | Should -Be $false
        }

        It '带空格的路径应处理' {
            Mock -ModuleName IPAP.ImageProcessor Test-Path -ParameterFilter { $Path -match 'Program Files' } { return $false }

            $result = Invoke-ImageUpscale -ImagePath 'C:\Program Files\test.jpg' -OutputDir 'C:\Program Files\output'

            $result | Should -Be $false
        }
    }
}
