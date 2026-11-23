#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Format-TomlString 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖 TOML 单行字符串转义：
    L1 正常转义、L2 边界（空串）、L3 特殊字符、L4 各转义分支、L5 输出可被 TOML 解析回原值。
#>

Describe 'Format-TomlString Unit Tests' -Tag 'Format-TomlString', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
        Import-Module (Join-Path $ProjectRoot 'output\RequiredModules\PSToml') -Force -Global

        function Invoke-FormatTomlString {
            param ([string]$Value)
            return InModuleScope IPAP -Parameters @{ V = $Value } -ScriptBlock { param($V) Format-TomlString -Value $V }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常路径' {
        It '普通文本应加双引号' {
            Invoke-FormatTomlString -Value 'abc' | Should -BeExactly '"abc"'
        }

        It '中文与日文应原样保留' {
            Invoke-FormatTomlString -Value '僕の愛する妻' | Should -BeExactly '"僕の愛する妻"'
        }
    }

    Context 'L2 边界' {
        It '空字符串应输出一对空引号' {
            Invoke-FormatTomlString -Value '' | Should -BeExactly '""'
        }
    }

    Context 'L3 特殊字符' {
        It '反斜杠应转义为两个反斜杠' {
            Invoke-FormatTomlString -Value 'C:\Images' | Should -BeExactly '"C:\\Images"'
        }

        It '双引号应转义' {
            Invoke-FormatTomlString -Value 'a"b' | Should -BeExactly '"a\"b"'
        }
    }

    Context 'L4 各转义分支' {
        It '换行制表符回车应分别转义' {
            Invoke-FormatTomlString -Value "a`nb`tc`rd" | Should -BeExactly '"a\nb\tc\rd"'
        }

        It '退格与换页应分别转义' {
            Invoke-FormatTomlString -Value "`b`f" | Should -BeExactly '"\b\f"'
        }

        It '其它控制字符应写成 \uXXXX' {
            Invoke-FormatTomlString -Value ([string][char]1) | Should -BeExactly '"\u0001"'
        }
    }

    Context 'L5 输出契约' {
        It '输出应能被 TOML 解析回原值' {
            [string]$Original = '路径 C:\a"b 与制表' + "`t" + '结尾'
            [string]$Formatted = Invoke-FormatTomlString -Value $Original
            $Parsed = ConvertFrom-Toml -InputObject "k = $Formatted"

            $Parsed.k | Should -BeExactly $Original
        }
    }
}
