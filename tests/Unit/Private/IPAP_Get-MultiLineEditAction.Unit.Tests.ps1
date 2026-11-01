#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-MultiLineEditAction 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖按键到编辑动作的纯函数：
    L1 正常编辑、L2 非法按键忽略、L3 边界输入、
    L4 全部分支、L5 动作对象五字段。
#>

Describe 'Get-MultiLineEditAction Unit Tests' -Tag 'Get-MultiLineEditAction', 'IPAP' {
    BeforeAll {
        # tests\Unit\Private → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global

        function New-TestKey {
            [CmdletBinding()]
            param(
                [char]$KeyChar,
                [ConsoleKey]$Key,
                [switch]$Control
            )
            return [ConsoleKeyInfo]::new($KeyChar, $Key, $false, $false, [bool]$Control)
        }

        function Invoke-Action {
            [CmdletBinding()]
            param(
                [ConsoleKeyInfo]$Key,
                [string]$CurrentLine,
                [string]$Prompt = ''
            )
            InModuleScope IPAP -Parameters @{ K = $Key; L = $CurrentLine; P = $Prompt } -ScriptBlock {
                param($K, $L, $P)
                Get-MultiLineEditAction -Key $K -CurrentLine $L -Prompt $P
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常编辑' {
        It '可打印字符应追加到当前行' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]'a') -Key ([ConsoleKey]::A)) -CurrentLine 'xy'

            $action.Type | Should -Be 'Append'
            $action.CurrentLine | Should -Be 'xya'
            $action.Text | Should -Be 'a'
            $action.LinesToAdd.Count | Should -Be 0
            $action.ClearLength | Should -Be 0
        }

        It '空格也应作为可打印字符追加' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]' ') -Key ([ConsoleKey]::Spacebar)) -CurrentLine 'ab'

            $action.Type | Should -Be 'Append'
            $action.CurrentLine | Should -Be 'ab '
            $action.Text | Should -Be ' '
        }
    }

    Context 'L2 非法按键忽略' {
        It '控制字符应被忽略' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]1) -Key ([ConsoleKey]::A) -Control) -CurrentLine 'ab'

            $action.Type | Should -Be 'Ignore'
            $action.CurrentLine | Should -Be 'ab'
            $action.LinesToAdd.Count | Should -Be 0
        }

        It '方向键应被忽略' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]0) -Key ([ConsoleKey]::LeftArrow)) -CurrentLine 'ab'

            $action.Type | Should -Be 'Ignore'
            $action.CurrentLine | Should -Be 'ab'
        }

        It 'Ctrl+D 缺少 Control 修饰时应被忽略' {
            # 仅 KeyChar 为 4 但没有 Control 修饰，不应误判为结束输入
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D)) -CurrentLine 'ab'

            $action.Type | Should -Be 'Ignore'
            $action.CurrentLine | Should -Be 'ab'
        }
    }

    Context 'L3 边界输入' {
        It '空行按 Enter 应追加一个空字符串' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]13) -Key ([ConsoleKey]::Enter)) -CurrentLine ''

            $action.Type | Should -Be 'NewLine'
            $action.CurrentLine | Should -Be ''
            $action.LinesToAdd.Count | Should -Be 1
            $action.LinesToAdd[0] | Should -Be ''
        }

        It '空行按 Backspace 应忽略' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]8) -Key ([ConsoleKey]::Backspace)) -CurrentLine ''

            $action.Type | Should -Be 'Ignore'
            $action.CurrentLine | Should -Be ''
            $action.LinesToAdd.Count | Should -Be 0
        }

        It '空行按 Delete 应忽略' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]0) -Key ([ConsoleKey]::Delete)) -CurrentLine ''

            $action.Type | Should -Be 'Ignore'
            $action.CurrentLine | Should -Be ''
            $action.ClearLength | Should -Be 0
        }

        It '空行按 Ctrl+D 应不追加并结束' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control) -CurrentLine ''

            $action.Type | Should -Be 'Submit'
            $action.CurrentLine | Should -Be ''
            $action.LinesToAdd.Count | Should -Be 0
        }
    }

    Context 'L4 全部分支' {
        It 'Enter 应追加当前行并清空' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]13) -Key ([ConsoleKey]::Enter)) -CurrentLine 'ab'

            $action.Type | Should -Be 'NewLine'
            $action.CurrentLine | Should -Be ''
            $action.LinesToAdd.Count | Should -Be 1
            $action.LinesToAdd[0] | Should -Be 'ab'
        }

        It 'Backspace 应删除最后一个字符' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]8) -Key ([ConsoleKey]::Backspace)) -CurrentLine 'ab'

            $action.Type | Should -Be 'Backspace'
            $action.CurrentLine | Should -Be 'a'
            $action.LinesToAdd.Count | Should -Be 0
        }

        It 'Delete 应清空整行并计算覆盖长度' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]0) -Key ([ConsoleKey]::Delete)) -CurrentLine 'ab' -Prompt 'XX'

            $action.Type | Should -Be 'ClearLine'
            $action.CurrentLine | Should -Be ''
            $action.ClearLength | Should -Be 4
            $action.LinesToAdd.Count | Should -Be 0
        }

        It 'Ctrl+D 应追加当前行并结束' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control) -CurrentLine 'ab'

            $action.Type | Should -Be 'Submit'
            $action.CurrentLine | Should -Be ''
            $action.LinesToAdd.Count | Should -Be 1
            $action.LinesToAdd[0] | Should -Be 'ab'
        }

        It 'Ctrl+d 变体也应结束' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]'d') -Key ([ConsoleKey]::D) -Control) -CurrentLine 'ab'

            $action.Type | Should -Be 'Submit'
            $action.LinesToAdd[0] | Should -Be 'ab'
        }
    }

    Context 'L5 输出字段验证' {
        It '动作对象应包含固定五字段' {
            $action = Invoke-Action -Key (New-TestKey -KeyChar ([char]'a') -Key ([ConsoleKey]::A)) -CurrentLine ''

            @($action.PSObject.Properties.Name | Sort-Object) |
                Should -Be @('ClearLength', 'CurrentLine', 'LinesToAdd', 'Text', 'Type')
        }
    }
}
