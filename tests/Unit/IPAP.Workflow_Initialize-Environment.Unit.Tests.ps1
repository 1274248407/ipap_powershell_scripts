#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Initialize-Environment 单元测试
.DESCRIPTION
    测试 IPAP.Workflow 模块的 Initialize-Environment 函数。
#>

Describe 'IPAP.Workflow Initialize-Environment Unit Tests' -Tag 'Initialize-Environment', 'IPAP.Workflow' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.Workflow Write-InfoLog {}
        Mock -ModuleName IPAP.Workflow Write-WarningLog {}
        Mock -ModuleName IPAP.Workflow Write-ErrorLog {}
        Mock -ModuleName IPAP.Workflow Get-RealCuganExePath { return 'C:\bin\realcugan-ncnn-vulkan.exe' }
        Mock -ModuleName IPAP.Workflow Get-Config {
            return @{
                paths        = @{ base_project_dir = 'C:\Projects'; project_dir_prefix = 'test_' }
                app_settings = @{ model_select = 'models-se'; max_workers = 8; upscale_timeout_sec = 600 }
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径' {
        It '应成功初始化环境' {
            $result = Initialize-Environment

            $result | Should -BeNullOrEmpty
        }

        It '应设置全局 RealCuganExePath 变量' {
            Initialize-Environment

            $Global:RealCuganExePath | Should -Not -BeNullOrEmpty
        }

        It '应设置全局 Settings 变量' {
            Initialize-Environment

            $Global:Settings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'exe 缺失处理' {
        It 'exe 不存在时应记录警告' {
            Mock -ModuleName IPAP.Workflow Get-RealCuganExePath { return $null }

            Initialize-Environment

            Assert-MockCalled -ModuleName IPAP.Workflow Write-WarningLog -Times 1
        }
    }
}
