#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ProjectLevel 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖项目统一等级归并：
    L1 正常归并     —— Context 'L1 正常归并'
    L2 异常输入     —— Context 'L2 非法输入'
    L3 边界数据     —— Context 'L3 边界数据'
    L4 分支与优先级 —— Context 'L4 基准集合分支'
    L5 输出契约     —— Context 'L5 输出契约验证'

    Get-ProjectLevel 是纯函数（只依赖入参），但会先记录 Error 日志再抛异常，
    因此仍 Mock Write-LogEntry 以隔离终端输出。
#>

Describe 'Get-ProjectLevel Unit Tests' -Tag 'Get-ProjectLevel', 'IPAP' {
    BeforeAll {
        # tests\Unit\Private → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -CommandName Write-LogEntry -ModuleName IPAP { }
    }

    Context 'L1 正常归并' {
        It '全部图片同一等级时应返回该等级（等级 <Level>）' -TestCases @(
            @{ Level = 0 }
            @{ Level = 1 }
            @{ Level = 2 }
        ) {
            param($Level)
            $Result = InModuleScope IPAP -Parameters @{ L = $Level } -ScriptBlock {
                param($L)
                Get-ProjectLevel -TextLevels @($L, $L, $L) -NonTextLevels @($L)
            }

            $Result | Should -Be $Level
        }

        It '有文字图多数为 Level 0 时应压制无文字图的 Level 2' {
            $Result = InModuleScope IPAP {
                Get-ProjectLevel -TextLevels @(0, 0, 1) -NonTextLevels @(2, 2, 2)
            }

            $Result | Should -Be 0
        }

        It '有文字图多数为 Level 1 时应返回 Level 1' {
            $Result = InModuleScope IPAP {
                Get-ProjectLevel -TextLevels @(1, 1, 1, 0) -NonTextLevels @(0)
            }

            $Result | Should -Be 1
        }

        It '有文字图多数为 Level 2 时应返回 Level 2' {
            $Result = InModuleScope IPAP {
                Get-ProjectLevel -TextLevels @(2, 2, 1) -NonTextLevels @()
            }

            $Result | Should -Be 2
        }
    }

    Context 'L2 非法输入' {
        It '两个集合都为空时应抛 ArgumentException' {
            { InModuleScope IPAP { Get-ProjectLevel -TextLevels @() -NonTextLevels @() } } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*分级结果为空*'
        }

        It '两个集合都为空时应记录一次 Error 日志' {
            { InModuleScope IPAP { Get-ProjectLevel -TextLevels @() -NonTextLevels @() } } | Should -Throw

            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP `
                -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It '等级为 -1 时应抛 ArgumentException' {
            { InModuleScope IPAP { Get-ProjectLevel -TextLevels @(0, -1) -NonTextLevels @() } } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*非法等级*'
        }

        It '等级为 3 时应抛 ArgumentException' {
            { InModuleScope IPAP { Get-ProjectLevel -TextLevels @(3) -NonTextLevels @() } } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*非法等级*'
        }

        It '无文字图集合中的非法等级也应被拒绝' {
            { InModuleScope IPAP { Get-ProjectLevel -TextLevels @() -NonTextLevels @(5) } } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*非法等级*'
        }
    }

    Context 'L3 边界数据' {
        It '只有一张有文字图时应返回其等级' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @(2) -NonTextLevels @() }

            $Result | Should -Be 2
        }

        It '两张等级不同（平票）时应取较高等级' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @(0, 1) -NonTextLevels @() }

            $Result | Should -Be 1
        }

        It '三张等级各不相同时应取最高的 Level 2' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @(0, 1, 2) -NonTextLevels @() }

            $Result | Should -Be 2
        }

        It 'Level 0 与 Level 2 平票时应取 Level 2' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @(0, 2) -NonTextLevels @() }

            $Result | Should -Be 2
        }

        It '多数票只差一票时仍按多数返回' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @(0, 0, 0, 1, 1) -NonTextLevels @() }

            $Result | Should -Be 0
        }

        It '大量同等级元素应稳定返回该等级' {
            $Result = InModuleScope IPAP {
                Get-ProjectLevel -TextLevels (@(1) * 700 + @(0) * 31) -NonTextLevels @()
            }

            $Result | Should -Be 1
        }
    }

    Context 'L4 基准集合分支' {
        It '无文字图为空时应只使用有文字图定级' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @(0, 1, 1) -NonTextLevels @() }

            $Result | Should -Be 1
        }

        It '有文字图为空时应退化为使用无文字图定级' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @() -NonTextLevels @(2, 2, 0) }

            $Result | Should -Be 2
        }

        It '有文字图非空时无文字图数量再多也不参与投票' {
            $Result = InModuleScope IPAP {
                Get-ProjectLevel -TextLevels @(0) -NonTextLevels (@(2) * 100)
            }

            $Result | Should -Be 0
        }

        It '省略 NonTextLevels 时应按空集合处理' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @(0, 0) }

            $Result | Should -Be 0
        }
    }

    Context 'L5 输出契约验证' {
        It '返回值应恰好是 [int] 且取值在 0-2 之间' {
            $Result = InModuleScope IPAP { Get-ProjectLevel -TextLevels @(1, 1) -NonTextLevels @() }

            $Result | Should -BeOfType ([int])
            $Result | Should -BeGreaterOrEqual 0
            $Result | Should -BeLessOrEqual 2
        }

        It '返回值不应附带任何额外管道对象' {
            $Result = @(InModuleScope IPAP { Get-ProjectLevel -TextLevels @(0, 0) -NonTextLevels @() })

            $Result.Count | Should -Be 1
        }
    }
}
