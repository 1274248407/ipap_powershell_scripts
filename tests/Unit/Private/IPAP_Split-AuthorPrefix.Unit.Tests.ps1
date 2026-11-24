#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Split-AuthorPrefix 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖「[作者] 前缀拆分」：
    L1 半角方括号、L2 无前缀与空串、L3 全角方括号与无空格、L4 前缀后无正文、L5 输出两个字符串属性。
#>

Describe 'Split-AuthorPrefix Unit Tests' -Tag 'Split-AuthorPrefix', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function Split-Title {
            param ([string]$Title)
            return InModuleScope IPAP -Parameters @{ T = $Title } -ScriptBlock { param($T) Split-AuthorPrefix -Title $T }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常路径' {
        It '半角方括号前缀应拆成两段' {
            $Result = Split-Title -Title '[アイチルワークス (林チェリー)] 僕の愛するおっとり妻'

            $Result.Prefix | Should -BeExactly '[アイチルワークス (林チェリー)]'
            $Result.Body | Should -BeExactly '僕の愛するおっとり妻'
        }
    }

    Context 'L2 边界' {
        It '没有前缀时 Prefix 为空、Body 为全文' {
            $Result = Split-Title -Title '僕の愛するおっとり妻'

            $Result.Prefix | Should -BeExactly ''
            $Result.Body | Should -BeExactly '僕の愛するおっとり妻'
        }

        It '空串应返回两个空字符串' {
            $Result = Split-Title -Title ''

            $Result.Prefix | Should -BeExactly ''
            $Result.Body | Should -BeExactly ''
        }
    }

    Context 'L3 其它写法' {
        It '全角方括号前缀应被识别' {
            $Result = Split-Title -Title '【作者】标题'

            $Result.Prefix | Should -BeExactly '【作者】'
            $Result.Body | Should -BeExactly '标题'
        }

        It '方括号后没有空格也应拆分' {
            $Result = Split-Title -Title '[作者]标题'

            $Result.Prefix | Should -BeExactly '[作者]'
            $Result.Body | Should -BeExactly '标题'
        }

        It '前缀前后的空白应被裁掉' {
            $Result = Split-Title -Title '  [作者]   标题  '

            $Result.Prefix | Should -BeExactly '[作者]'
            $Result.Body | Should -BeExactly '标题'
        }
    }

    Context 'L4 没有正文' {
        It '只有前缀时 Body 为空' {
            $Result = Split-Title -Title '[作者]'

            $Result.Prefix | Should -BeExactly '[作者]'
            $Result.Body | Should -BeExactly ''
        }
    }

    Context 'L5 输出契约' {
        It '应返回两个字符串属性' {
            $Result = Split-Title -Title '[作者] 标题'

            , $Result | Should -HaveCount 1
            $Result.Prefix | Should -BeOfType ([string])
            $Result.Body | Should -BeOfType ([string])
        }
    }
}
