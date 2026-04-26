#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Core - Initialize-Environment 验收测试
.DESCRIPTION
    验收测试 Initialize-Environment 函数在真实环境中的初始化能力。
#>

Describe 'Initialize-Environment Acceptance Tests' -Tag 'Initialize-Environment', 'IPAP.Core', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.Core module not found at: $ModulePath" -ForegroundColor Red
        }
    }

    AfterAll {
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '正常初始化 - Normal Initialization' {
        It '应成功初始化并设置全局变量' {
            Initialize-Environment

            $Global:RealCuganExePath | Should -Not -BeNullOrEmpty
            $Global:Settings | Should -Not -BeNullOrEmpty
        }

        It 'Settings 应包含正确的结构' {
            Initialize-Environment

            $Global:Settings | Should -BeOfType [System.Hashtable]
            $Global:Settings.Keys | Should -Contain 'paths'
            $Global:Settings.Keys | Should -Contain 'app_settings'
        }

        It 'app_settings 应包含必要的配置项' {
            Initialize-Environment

            $Global:Settings.app_settings.Keys | Should -Contain 'model_select'
            $Global:Settings.app_settings.Keys | Should -Contain 'max_workers'
            $Global:Settings.app_settings.Keys | Should -Contain 'upscale_timeout_sec'
        }
    }

    Context '全局变量状态测试' {
        It 'RealCuganExePath 应包含有效路径或 $null' {
            Initialize-Environment

            if ($Global:RealCuganExePath)
            {
                $Global:RealCuganExePath | Should -Match 'realcugan.*\.exe$'
            }
            else
            {
                $Global:RealCuganExePath | Should -BeNullOrEmpty
            }
        }

        It 'Settings paths 应包含正确字段' {
            Initialize-Environment

            $Global:Settings.paths.Keys | Should -Contain 'base_project_dir'
            $Global:Settings.paths.Keys | Should -Contain 'project_dir_prefix'
        }
    }

    Context '重复初始化测试' {
        It '应允许重复初始化而不报错' {
            Initialize-Environment
            { Initialize-Environment } | Should -Not -Throw
        }

        It '重复初始化应返回相同结果' {
            Initialize-Environment
            $firstResult = $Global:RealCuganExePath

            Initialize-Environment
            $secondResult = $Global:RealCuganExePath

            $firstResult | Should -Be $secondResult
        }
    }
}
