#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Test-ChineseText 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖「是否可读中文」的判定：
    L1 纯中文、L2 空串与纯英文、L3 日文与夹带假名的文本、L4 汉字/假名组合边界、L5 返回布尔。

    规则是「没有汉字 → 否；出现任何假名 → 否」。带日文作者前缀的书名由
    Test-NeedsTranslation 先剥前缀，所以这里测的是「传进来的文本本身」。
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
        It '纯简体中文应判定为中文' {
            Test-IsChinese -Text '我心爱的温婉妻子被夺走并怀上了别人的孩子' | Should -BeTrue
        }

        It '中文标点与数字不影响判定' {
            Test-IsChinese -Text '第 1 卷：妻子的秘密（上）' | Should -BeTrue
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

    Context 'L3 日文与夹带假名' {
        It '整句日文应判定为不是中文' {
            Test-IsChinese -Text '僕の愛するおっとり妻が寝取られて孕まされた話' | Should -BeFalse
        }

        It '夹一个假名的中文应判定为不是中文' {
            Test-IsChinese -Text '我あ心爱的妻子' | Should -BeFalse
        }

        It '带日文作者前缀的整串应判定为不是中文（前缀由调用方先剥掉）' {
            [string]$Text = '[アイチルワークス (林チェリー)] 我心爱的温婉妻子被夺走并怀上了别人的孩子'
            Test-IsChinese -Text $Text | Should -BeFalse
        }

        It '半角片假名也应判定为不是中文' {
            Test-IsChinese -Text ('我' + [char]0xFF71 + '心爱的妻子') | Should -BeFalse
        }
    }

    Context 'L4 数量边界' {
        It '汉字多于假名也不应判定为中文' {
            # 早期规则「假名少于汉字」会让这条通过；它不是可读的中文
            Test-IsChinese -Text 'あい漢語書' | Should -BeFalse
        }

        It '假名与汉字数量相等时应判定为不是中文' {
            Test-IsChinese -Text 'あい漢語' | Should -BeFalse
        }

        It '单个汉字应判定为中文' {
            Test-IsChinese -Text '漢' | Should -BeTrue
        }

        It '长中文里引用一个日文术语应仍判定为中文' {
            # 真实场景：2215 字的中文简介里出现了「ボテ腹」
            [string]$Text = ('妻子的日常描写占位文字' * 12) + '成了所谓的"ボテ腹"（大肚孕妇）'
            Test-IsChinese -Text $Text | Should -BeTrue
        }

        It '长文本里假名占比过高时应判定为不是中文' {
            [string]$Text = ('妻の日常' * 30) + ('中文占位' * 5)
            Test-IsChinese -Text $Text | Should -BeFalse
        }
    }

    Context 'L5 输出契约' {
        It '应返回布尔值而不是字符串' {
            Test-IsChinese -Text '测试' | Should -BeOfType ([bool])
        }
    }
}
