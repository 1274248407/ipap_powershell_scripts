#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Initialize-ImageProcessor 单元测试
.DESCRIPTION
    测试 Initialize-ImageProcessor 函数的初始化逻辑。
#>

Describe 'Initialize-ImageProcessor Unit Tests' -Tag 'Initialize-ImageProcessor', 'IPAP.ImageProcessor' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.ImageProcessor Write-InfoLog {}
        Mock -ModuleName IPAP.ImageProcessor Write-WarningLog {}
        Mock -ModuleName IPAP.ImageProcessor Write-ErrorLog {}
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '应设置全局 RealCuganExePath 变量' {
            Mock -ModuleName IPAP.ImageProcessor Get-RealCuganExePath {
                $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
                return 'C:\bin\realcugan-ncnn-vulkan.exe'
            }

            Initialize-ImageProcessor

            $Global:RealCuganExePath | Should -Not -BeNullOrEmpty
            $Global:RealCuganExePath | Should -Match 'realcugan.*\.exe$'
        }
    }

    Context 'exe 缺失处理' {
        It 'exe 不存在时应记录警告' {
            Mock -ModuleName IPAP.ImageProcessor Get-RealCuganExePath {
                $Global:RealCuganExePath = $null
                return $null
            }

            Initialize-ImageProcessor

            Assert-MockCalled -ModuleName IPAP.ImageProcessor Write-WarningLog -Times 1
        }

        It 'exe 缺失时 RealCuganExePath 应为 $null' {
            Mock -ModuleName IPAP.ImageProcessor Get-RealCuganExePath {
                $Global:RealCuganExePath = $null
                return $null
            }

            Initialize-ImageProcessor

            $Global:RealCuganExePath | Should -BeNullOrEmpty
        }
    }

    Context '重复初始化测试' {
        It '应允许重复初始化' {
            Mock -ModuleName IPAP.ImageProcessor Get-RealCuganExePath {
                $Global:RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
                return 'C:\bin\realcugan-ncnn-vulkan.exe'
            }

            Initialize-ImageProcessor
            { Initialize-ImageProcessor } | Should -Not -Throw
        }
    }
}
