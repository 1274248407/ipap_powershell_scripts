#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Core - Initialize-Environment 单元测试
.DESCRIPTION
    测试 Initialize-Environment 函数的初始化逻辑和环境设置。
#>

Describe 'Initialize-Environment Unit Tests' -Tag 'Initialize-Environment', 'IPAP.Core' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.Core Write-InfoLog {}
        Mock -ModuleName IPAP.Core Write-WarningLog {}
        Mock -ModuleName IPAP.Core Write-ErrorLog {}
        Mock -ModuleName IPAP.Core Get-RealCuganExePath { return 'C:\bin\realcugan-ncnn-vulkan.exe' }
        Mock -ModuleName IPAP.Core Get-Config {
            return @{
                paths        = @{ base_project_dir = 'C:\Projects'; project_dir_prefix = 'test_' }
                app_settings = @{ model_select = 'models-se'; max_workers = 8; upscale_timeout_sec = 600 }
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '应成功初始化环境' {
            $result = Initialize-Environment

            $result | Should -BeNullOrEmpty
        }

        It '应设置全局 RealCuganExePath 变量' {
            Initialize-Environment

            $Global:RealCuganExePath | Should -Not -BeNullOrEmpty
            $Global:RealCuganExePath | Should -Match 'realcugan-ncnn-vulkan\.exe$'
        }

        It '应设置全局 Settings 变量' {
            Initialize-Environment

            $Global:Settings | Should -Not -BeNullOrEmpty
            $Global:Settings.paths | Should -Not -BeNullOrEmpty
            $Global:Settings.app_settings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'exe 缺失处理 - Exe Missing Handling' {
        It 'exe 不存在时应记录警告' {
            Mock -ModuleName IPAP.Core Get-RealCuganExePath { return $null }
            Mock -ModuleName IPAP.Core Write-WarningLog {}

            Initialize-Environment

            Assert-MockCalled -ModuleName IPAP.Core Write-WarningLog -Times 1
        }

        It 'exe 缺失时 Settings 仍应被设置' {
            Mock -ModuleName IPAP.Core Get-RealCuganExePath { return $null }

            Initialize-Environment

            $Global:Settings | Should -Not -BeNullOrEmpty
        }
    }

    Context '重复初始化测试 - Re-initialization' {
        It '应允许重复初始化' {
            Initialize-Environment
            { Initialize-Environment } | Should -Not -Throw
        }

        It '重复初始化应覆盖之前的值' {
            Initialize-Environment

            $firstValue = $Global:RealCuganExePath

            Initialize-Environment

            $Global:RealCuganExePath | Should -Be $firstValue
        }
    }
}
