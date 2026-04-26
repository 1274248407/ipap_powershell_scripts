#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Initialize-Environment 验收测试
.DESCRIPTION
    验收测试 IPAP.Workflow 模块的 Initialize-Environment 函数。
#>

Describe 'IPAP.Workflow Initialize-Environment Acceptance Tests' -Tag 'Initialize-Environment', 'IPAP.Workflow', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.Workflow module not found at: $ModulePath" -ForegroundColor Red
        }
    }

    AfterAll {
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
    }

    Context '正常初始化' {
        It '应成功初始化环境' {
            Initialize-Environment

            $Global:RealCuganExePath | Should -Not -BeNullOrEmpty
            $Global:Settings | Should -Not -BeNullOrEmpty
        }

        It 'Settings 应包含正确的结构' {
            Initialize-Environment

            $Global:Settings.Keys | Should -Contain 'paths'
            $Global:Settings.Keys | Should -Contain 'app_settings'
        }
    }

    Context '重复初始化测试' {
        It '应允许重复初始化' {
            Initialize-Environment
            { Initialize-Environment } | Should -Not -Throw
        }
    }
}
