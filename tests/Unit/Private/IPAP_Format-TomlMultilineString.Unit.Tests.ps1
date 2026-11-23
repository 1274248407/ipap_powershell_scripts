#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Format-TomlMultilineString 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖多行字符串格式化：
    L1 字面量分支、L2 空串、L3 需要退回双引号的分支（含三连引号 / 以单引号结尾）、
    L4 换行保留、L5 输出可被 TOML 解析回原值。
#>

Describe 'Format-TomlMultilineString Unit Tests' -Tag 'Format-TomlMultilineString', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
        Import-Module (Join-Path $ProjectRoot 'output\RequiredModules\PSToml') -Force -Global

        function Invoke-FormatTomlMultiline {
            param ([string]$Value)
            return InModuleScope IPAP -Parameters @{ V = $Value } -ScriptBlock { param($V) Format-TomlMultilineString -Value $V }
        }

        function Get-RoundTripValue {
            param ([string]$Value)
            [string]$Formatted = Invoke-FormatTomlMultiline -Value $Value
            return (ConvertFrom-Toml -InputObject "k = $Formatted").k
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常路径' {
        It '普通多行文本应使用三引号字面量' {
            [string]$Text = "第一行`n第二行"

            Invoke-FormatTomlMultiline -Value $Text | Should -BeExactly "'''`n第一行`n第二行'''"
        }
    }

    Context 'L2 边界' {
        It '空文本应回读为空串' {
            Get-RoundTripValue -Value '' | Should -BeExactly ''
        }
    }

    Context 'L3 退回双引号分支' {
        It '内容含三连单引号时应改用双引号包裹' {
            [string]$Text = "a'''b"

            Invoke-FormatTomlMultiline -Value $Text | Should -BeLike '"""*'
            Get-RoundTripValue -Value $Text | Should -BeExactly $Text
        }

        It '内容以单引号结尾时应改用双引号包裹' {
            [string]$Text = "结尾'"

            Invoke-FormatTomlMultiline -Value $Text | Should -BeLike '"""*'
            Get-RoundTripValue -Value $Text | Should -BeExactly $Text
        }

        It '双引号包裹时反斜杠应被转义' {
            [string]$Text = "a'''b\c"

            Get-RoundTripValue -Value $Text | Should -BeExactly $Text
        }
    }

    Context 'L4 换行保留' {
        It '字面量分支应保留反斜杠不转义' {
            [string]$Text = "C:\a\b"

            Invoke-FormatTomlMultiline -Value $Text | Should -BeExactly "'''`nC:\a\b'''"
            Get-RoundTripValue -Value $Text | Should -BeExactly $Text
        }

        It '结尾换行应保留' {
            [string]$Text = "第一行`n"

            Get-RoundTripValue -Value $Text | Should -BeExactly $Text
        }
    }

    Context 'L5 输出契约' {
        It '多段日文与中文应逐字节回读一致' {
            [string]$Text = "▲あらすじ`n------------------------------------------------------------`n`n妻子「沙织」性格温婉。"

            Get-RoundTripValue -Value $Text | Should -BeExactly $Text
        }
    }
}
