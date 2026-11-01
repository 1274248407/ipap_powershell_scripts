#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Read-MultiLineInput 单元测试
.DESCRIPTION
    公共函数只负责参数与返回值透传；真实按键读取与循环
    由 Invoke-MultiLineReader / Get-MultiLineEditAction 的单测覆盖。
#>

Describe 'Read-MultiLineInput Unit Tests' -Tag 'Read-MultiLineInput', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '参数与返回值透传' {
        It '应将 Prompt 透传给 Invoke-MultiLineReader 并返回其行数组' {
            Mock -CommandName Invoke-MultiLineReader -ModuleName IPAP { return @('x', 'y') }

            $result = Read-MultiLineInput -Prompt 'p'

            @($result).Count | Should -Be 2
            $result[0] | Should -Be 'x'
            $result[1] | Should -Be 'y'
            Should -Invoke -CommandName Invoke-MultiLineReader -ModuleName IPAP -ParameterFilter {
                $Prompt -eq 'p'
            } -Times 1 -Exactly
        }

        It '内核无输出时应返回空' {
            Mock -CommandName Invoke-MultiLineReader -ModuleName IPAP { return @() }

            $result = Read-MultiLineInput -Prompt 'p'

            $result | Should -BeNullOrEmpty
        }
    }
}
