#Requires -Modules Pester

<#
.SYNOPSIS
    Main.ps1 - Initialize-Environment 单元测试
.DESCRIPTION
    测试 Main.ps1 中定义的 Initialize-Environment 函数。
#>

Describe 'Main Initialize-Environment Unit Tests' -Tag 'Initialize-Environment', 'Main' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
        $MainScriptPath = Join-Path $ProjectRoot 'Main.ps1'

        if (Test-Path $MainScriptPath)
        {
            . $MainScriptPath
        }

        Mock Write-InfoLog {}
        Mock Write-WarningLog {}
        Mock Get-RealCuganExePath { return 'C:\bin\realcugan-ncnn-vulkan.exe' }
        Mock Get-Config {
            return @{
                paths        = @{ base_project_dir = 'C:\Projects'; project_dir_prefix = 'test_' }
                app_settings = @{ model_select = 'models-se'; max_workers = 8; upscale_timeout_sec = 600 }
            }
        }
    }

    Context '正常执行路径' {
        It '应成功初始化环境' {
            Initialize-Environment

            $Global:RealCuganExePath | Should -Not -BeNullOrEmpty
            $Global:Settings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'exe 缺失处理' {
        It 'exe 不存在时应记录警告' {
            Mock Get-RealCuganExePath { return $null }

            Initialize-Environment

            Assert-MockCalled Write-WarningLog -Times 1
        }
    }

    Context '重复初始化测试' {
        It '应允许重复初始化' {
            Initialize-Environment
            { Initialize-Environment } | Should -Not -Throw
        }
    }
}
