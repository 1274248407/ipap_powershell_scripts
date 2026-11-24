#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Test-NeedsTranslation 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖「中文字段是否需要重新翻译」：
    L1 正常中文、L2 空与空白、L3 占位符与原文相同、L4 不是中文、L5 返回布尔。
#>

Describe 'Test-NeedsTranslation Unit Tests' -Tag 'Test-NeedsTranslation', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function Test-Needs {
            param ([string]$Value, [string]$Placeholder = '', [string]$Original = '')
            return InModuleScope IPAP -Parameters @{ V = $Value; P = $Placeholder; O = $Original } -ScriptBlock {
                param($V, $P, $O)
                Test-NeedsTranslation -Value $V -Placeholder $P -Original $O
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常路径' {
        It '已填好的中文应判定为不需要翻译' {
            Test-Needs -Value '我心爱的妻子' -Placeholder '中文译名' -Original '僕の妻' | Should -BeFalse
        }
    }

    Context 'L2 空与空白' {
        It '空串应判定为需要翻译' {
            Test-Needs -Value '' | Should -BeTrue
        }

        It '纯空白应判定为需要翻译' {
            Test-Needs -Value "   `t " | Should -BeTrue
        }
    }

    Context 'L3 占位符与原文' {
        It '与占位文本相同应判定为需要翻译' {
            Test-Needs -Value '中文译名' -Placeholder '中文译名' | Should -BeTrue
        }

        It '与原文相同应判定为需要翻译' {
            Test-Needs -Value '僕の妻' -Original '僕の妻' | Should -BeTrue
        }

        It '未提供占位文本时不应误判为占位符' {
            Test-Needs -Value '我心爱的妻子' -Placeholder '' -Original '僕の妻' | Should -BeFalse
        }
    }

    Context 'L4 不是中文' {
        It '纯英文应判定为需要翻译' {
            Test-Needs -Value 'My Beloved Wife' | Should -BeTrue
        }

        It '整句日文应判定为需要翻译' {
            Test-Needs -Value '僕の愛するおっとり妻' | Should -BeTrue
        }

        It '带日文作者前缀的中文书名不应被误判为日文' {
            Test-Needs -Value '[アイチルワークス (林チェリー)] 我心爱的妻子' | Should -BeFalse
        }
    }

    Context 'L5 输出契约' {
        It '应返回布尔值' {
            Test-Needs -Value '测试' | Should -BeOfType ([bool])
        }
    }
}
