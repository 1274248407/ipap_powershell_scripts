#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Test-ChineseText 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖中/日文启发式判定：
    L1 纯中文、L2 空串与纯英文、L3 日文与「中文+日文作者前缀」、L4 汉字/假名数量边界、L5 返回布尔。
#>

Describe 'Test-ChineseText Unit Tests' -Tag 'Test-ChineseText', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function Test-IsChinese {
            param ([string]$Text)
            return InModuleScope IPAP -Parameters @{ T = $Text } -ScriptBlock { param($T) Test-ChineseText -Text $T }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常路径' {
        It '纯中文应判定为中文' {
            Test-IsChinese -Text '我心爱的温婉妻子被夺走并怀上了别人的孩子' | Should -BeTrue
        }
    }

    Context 'L2 边界' {
        It '空串应判定为不是中文' {
            Test-IsChinese -Text '' | Should -BeFalse
        }

        It '纯英文应判定为不是中文' {
            Test-IsChinese -Text 'My Beloved Wife' | Should -BeFalse
        }

        It '纯符号应判定为不是中文' {
            Test-IsChinese -Text '[] () ---' | Should -BeFalse
        }
    }

    Context 'L3 日文与作者前缀' {
        It '整句日文（假名多于汉字）应判定为不是中文' {
            Test-IsChinese -Text '僕の愛するおっとり妻が寝取られて孕まされた話' | Should -BeFalse
        }

        It '中文书名带日文作者前缀时应仍判定为中文' {
            [string]$Text = '[アイチルワークス (林チェリー)] 我心爱的温婉妻子被夺走并怀上了别人的孩子'
            Test-IsChinese -Text $Text | Should -BeTrue
        }

        It '纯假名应判定为不是中文' {
            Test-IsChinese -Text 'おっとりむすめ' | Should -BeFalse
        }
    }

    Context 'L4 数量边界' {
        It '假名与汉字数量相等时应判定为不是中文' {
            # 假名 2（あい）、汉字 2（漢語）→ 相等即按日文处理
            Test-IsChinese -Text 'あい漢語' | Should -BeFalse
        }

        It '汉字比假名多一个时应判定为中文' {
            Test-IsChinese -Text 'あい漢語書' | Should -BeTrue
        }
    }

    Context 'L5 输出契约' {
        It '应返回布尔值而不是字符串' {
            Test-IsChinese -Text '测试' | Should -BeOfType ([bool])
        }
    }
}
