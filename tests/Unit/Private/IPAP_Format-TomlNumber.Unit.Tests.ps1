#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Format-TomlNumber 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖数字格式化：
    L1 两位小数、L2 整数、L3 末尾 0 去除与四舍五入、L4 Decimals 为 0 的分支、L5 输出不含千分位与本地化逗号。
#>

Describe 'Format-TomlNumber Unit Tests' -Tag 'Format-TomlNumber', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function Invoke-FormatTomlNumber {
            param ([double]$Value, [int]$Decimals = 2)
            return InModuleScope IPAP -Parameters @{ V = $Value; D = $Decimals } -ScriptBlock {
                param($V, $D)
                Format-TomlNumber -Value $V -Decimals $D
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常路径' {
        It '两位小数应原样输出' {
            Invoke-FormatTomlNumber -Value 5.21 | Should -BeExactly '5.21'
        }
    }

    Context 'L2 整数' {
        It '整数不应带小数点' {
            Invoke-FormatTomlNumber -Value 1920 | Should -BeExactly '1920'
        }
    }

    Context 'L3 边界数据' {
        It '末尾多余的 0 应去掉' {
            Invoke-FormatTomlNumber -Value 612.5 | Should -BeExactly '612.5'
        }

        It '超过两位小数应四舍五入到两位' {
            Invoke-FormatTomlNumber -Value 61.1449 | Should -BeExactly '61.14'
        }

        It '零应输出 0' {
            Invoke-FormatTomlNumber -Value 0 | Should -BeExactly '0'
        }
    }

    Context 'L4 分支' {
        It 'Decimals 为 0 时应输出整数' {
            Invoke-FormatTomlNumber -Value 6.4 -Decimals 0 | Should -BeExactly '6'
        }
    }

    Context 'L5 输出契约' {
        It '大数不应带千分位分隔符' {
            Invoke-FormatTomlNumber -Value 1234567.5 | Should -BeExactly '1234567.5'
        }

        It '小数分隔符应固定为点而非逗号' {
            Invoke-FormatTomlNumber -Value 1.5 | Should -Not -Match ','
        }
    }
}
