#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Read-TrimmedInput 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖交互输入的包装函数：
    L1 正常输入与 Trim、L2 非交互环境（EOF / $null）、L3 纯空白与内部空白、
    L4 提示透传与分支、L5 返回类型与单值。

    重点回归：Read-Host 在 stdin EOF 时返回 AutomationNull，它与 $null 相等
    但不能调用方法；直接 .Trim() 会抛「不能对值为 Null 的表达式调用方法」。
    本函数的职责就是把这种返回值统一成空字符串。
#>

Describe 'Read-TrimmedInput Unit Tests' -Tag 'Read-TrimmedInput', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常输入' {
        It '应返回去除首尾空白后的内容' {
            Mock -CommandName Read-Host -ModuleName IPAP { return '   C:\Images   ' }

            $Result = InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' }

            $Result | Should -BeExactly 'C:\Images'
        }

        It '应原样返回没有多余空白的内容' {
            Mock -CommandName Read-Host -ModuleName IPAP { return 'D:\a\b' }

            $Result = InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' }

            $Result | Should -BeExactly 'D:\a\b'
        }
    }

    Context 'L2 非交互环境' {
        It 'Read-Host 无输出（EOF）时应返回空字符串而不是抛异常' {
            Mock -CommandName Read-Host -ModuleName IPAP { }

            { InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' } } | Should -Not -Throw
            $Result = InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' }
            $Result | Should -BeExactly ''
        }

        It 'Read-Host 返回 $null 时应返回空字符串' {
            Mock -CommandName Read-Host -ModuleName IPAP { return $null }

            $Result = InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' }

            $Result | Should -BeExactly ''
        }
    }

    Context 'L3 边界数据' {
        It '纯空白输入应返回空字符串' {
            Mock -CommandName Read-Host -ModuleName IPAP { return "  `t " }

            $Result = InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' }

            $Result | Should -BeExactly ''
        }

        It '内部空白应保留，只裁剪首尾' {
            Mock -CommandName Read-Host -ModuleName IPAP { return '  a b  c  ' }

            $Result = InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' }

            $Result | Should -BeExactly 'a b  c'
        }

        It '超长输入应完整保留' {
            Mock -CommandName Read-Host -ModuleName IPAP { return ('x' * 5000) }

            $Result = InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' }

            $Result.Length | Should -Be 5000
        }
    }

    Context 'L4 提示与分支' {
        It '应把 Prompt 原样传给 Read-Host' {
            Mock -CommandName Read-Host -ModuleName IPAP { return 'v' }

            $null = InModuleScope IPAP { Read-TrimmedInput -Prompt '请输入源图片目录' }

            Should -Invoke -ModuleName IPAP Read-Host -Times 1 -Exactly `
                -ParameterFilter { $Prompt -eq '请输入源图片目录' }
        }

        It 'Prompt 为空字符串时应被参数绑定拒绝' {
            { InModuleScope IPAP { Read-TrimmedInput -Prompt '' } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }
    }

    Context 'L5 输出契约' {
        It '应始终返回单个字符串（非交互环境也不返回 $null）' {
            Mock -CommandName Read-Host -ModuleName IPAP { }

            $Result = @(InModuleScope IPAP { Read-TrimmedInput -Prompt 'p' })

            $Result.Count | Should -Be 1
            $Result[0] | Should -BeOfType [string]
        }
    }
}
