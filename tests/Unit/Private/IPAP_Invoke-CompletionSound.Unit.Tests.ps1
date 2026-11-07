#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Invoke-CompletionSound 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 的 L1-L5 覆盖完成提示音：
    - L1 正常流程：注入的发声实现被调用恰好一次，成功路径不写日志
    - L2 异常流程：发声实现抛异常时记录 Warning，不向上抛出（装饰性副作用失败不中断调用方）
    - L3 边界数据：空脚本块视为成功（无可执行内容）
    - L4 分支覆盖：try（成功）与 catch（失败）两条分支分别由 L1、L2 覆盖
    - L5 输出字段：函数无 Success 流输出；失败日志的 Level 与 Message 字段精确
    提示音是私有函数，测试统一经 InModuleScope 调用；通过 -PlaySound 注入假实现，
    不产生真实声音。跨作用域计数用 -Parameters 传入 Hashtable（引用类型）。
#>

Describe 'Invoke-CompletionSound Unit Tests' -Tag 'Invoke-CompletionSound', 'IPAP' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -CommandName Write-LogEntry -ModuleName IPAP { }
    }

    Context 'L1 正常流程' {
        It '注入的发声实现应被调用恰好一次且不写日志' {
            $State = @{ Played = 0 }

            InModuleScope IPAP -Parameters @{ S = $State } -ScriptBlock {
                param($S)
                Invoke-CompletionSound -PlaySound { $S.Played++ }
            }

            $State.Played | Should -Be 1
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -Times 0 -Exactly
        }
    }

    Context 'L2 异常流程' {
        It '发声实现抛异常时应记录 Warning 且不向上抛出' {
            { InModuleScope IPAP -ScriptBlock { Invoke-CompletionSound -PlaySound { throw 'audio device unavailable' } } } |
                Should -Not -Throw

            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Warning' -and $Message -eq '提示音播放失败: audio device unavailable'
            } -Times 1 -Exactly
        }
    }

    Context 'L3 边界数据' {
        It '空脚本块应视为成功且不写日志' {
            { InModuleScope IPAP -ScriptBlock { Invoke-CompletionSound -PlaySound { } } } | Should -Not -Throw

            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -Times 0 -Exactly
        }
    }

    # L4：try（成功）与 catch（失败）两条分支分别由 L1、L2 覆盖，无需重复造用例。

    Context 'L5 输出字段' {
        It '发声实现返回的值不应泄漏到 Success 流（void 契约）' {
            $Result = InModuleScope IPAP -ScriptBlock {
                Invoke-CompletionSound -PlaySound { 'noise' }
            }

            $Result | Should -BeNullOrEmpty
        }
    }
}
