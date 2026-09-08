#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Write-LogEntry 单元测试
.DESCRIPTION
    测试 Write-LogEntry 函数的日志输出、错误抛出和空消息防御逻辑。
    覆盖 bug 修复：Error 级别传入空 Message 时 throw 空字符串导致崩溃。
#>

Describe 'Write-LogEntry Unit Tests' -Tag 'Write-LogEntry', 'IPAP' {
    BeforeAll {
        # tests\Unit\Private → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # Mock Write-Host 避免测试输出污染控制台
        Mock -CommandName Write-Host -ModuleName IPAP { }
    }

    Context '非 Error 级别 - 不应抛出异常' {
        It 'Info 级别不应抛出异常' {
            { Write-LogEntry -Level Info -Message '测试信息' -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Success 级别不应抛出异常' {
            { Write-LogEntry -Level Success -Message '测试成功' -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Warning 级别不应抛出异常' {
            { Write-LogEntry -Level Warning -Message '测试警告' -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'Error 级别 - 正常消息' {
        It 'Error 级别应抛出与 Message 相同的异常' {
            { Write-LogEntry -Level Error -Message '测试错误消息' -ErrorAction Stop } | Should -Throw -ExpectedMessage '测试错误消息'
        }
    }

    Context 'Error 级别 - 空消息防御（bug 修复验证）' {
        It '空字符串消息应抛出兜底错误而非崩溃' {
            { Write-LogEntry -Level Error -Message '' -ErrorAction Stop } | Should -Throw -ExpectedMessage '未知错误（空消息）'
        }

        It 'null 消息应抛出兜底错误而非崩溃' {
            { Write-LogEntry -Level Error -Message $null -ErrorAction Stop } | Should -Throw -ExpectedMessage '未知错误（空消息）'
        }
    }
}
