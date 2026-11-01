#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Invoke-MultiLineReader 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖多行输入循环：
    L1 多行累积、L2 空输入、L3 空行边界、
    L4 全部分支与渲染、L5 返回行数组逐项验证。
    ReadKey / WriteOutput 全部注入假实现，不触碰真实控制台。
#>

Describe 'Invoke-MultiLineReader Unit Tests' -Tag 'Invoke-MultiLineReader', 'IPAP' {
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

        function Invoke-ReaderTest {
            [CmdletBinding()]
            param(
                [ConsoleKeyInfo[]]$Keys,
                [string]$Prompt = ''
            )
            InModuleScope IPAP -Parameters @{ KeyList = $Keys; PromptText = $Prompt } -ScriptBlock {
                param($KeyList, $PromptText)

                $script:TestKeyQueue = [System.Collections.Generic.Queue[ConsoleKeyInfo]]::new()
                foreach ($key in $KeyList) { $script:TestKeyQueue.Enqueue($key) }
                $script:TestRenderCalls = [System.Collections.Generic.List[object]]::new()

                [scriptblock]$readKey = { return $script:TestKeyQueue.Dequeue() }
                [scriptblock]$writeOutput = {
                    param([string]$Text, [switch]$NoNewline)
                    $script:TestRenderCalls.Add([PSCustomObject]@{
                            Text       = $Text
                            NoNewline  = [bool]$NoNewline
                        })
                }

                [string[]]$lines = @(Invoke-MultiLineReader -ReadKey $readKey -WriteOutput $writeOutput -Prompt $PromptText)
                return [PSCustomObject]@{
                    Lines       = $lines
                    RenderCalls = $script:TestRenderCalls.ToArray()
                }
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 多行累积' {
        It 'Enter 应提交当前行，Ctrl+D 应提交最后一行并结束' {
            $keys = @(
                (New-TestKey -KeyChar ([char]'a') -Key ([ConsoleKey]::A))
                (New-TestKey -KeyChar ([char]'b') -Key ([ConsoleKey]::B))
                (New-TestKey -KeyChar ([char]13) -Key ([ConsoleKey]::Enter))
                (New-TestKey -KeyChar ([char]'c') -Key ([ConsoleKey]::C))
                (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control)
            )

            $result = Invoke-ReaderTest -Keys $keys

            $result.Lines.Count | Should -Be 2
            $result.Lines[0] | Should -Be 'ab'
            $result.Lines[1] | Should -Be 'c'
            # 渲染：a、b、换行、c；Ctrl+D 不渲染
            $result.RenderCalls.Count | Should -Be 4
            $result.RenderCalls[0].Text | Should -Be 'a'
            $result.RenderCalls[0].NoNewline | Should -BeTrue
            $result.RenderCalls[2].Text | Should -Be ''
            $result.RenderCalls[2].NoNewline | Should -BeFalse
        }
    }

    Context 'L2 空输入' {
        It '直接按 Ctrl+D 应返回空结果且不渲染' {
            $keys = @(
                (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control)
            )

            $result = Invoke-ReaderTest -Keys $keys

            $result.Lines.Count | Should -Be 0
            $result.RenderCalls.Count | Should -Be 0
        }

        It '提示语应在循环前输出一次' {
            $keys = @(
                (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control)
            )

            $result = Invoke-ReaderTest -Keys $keys -Prompt 'P'

            $result.RenderCalls.Count | Should -Be 1
            $result.RenderCalls[0].Text | Should -Be 'P'
            $result.RenderCalls[0].NoNewline | Should -BeFalse
        }
    }

    Context 'L3 空行边界' {
        It '连续空行 Enter 应保留空字符串行' {
            $keys = @(
                (New-TestKey -KeyChar ([char]13) -Key ([ConsoleKey]::Enter))
                (New-TestKey -KeyChar ([char]13) -Key ([ConsoleKey]::Enter))
                (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control)
            )

            $result = Invoke-ReaderTest -Keys $keys

            $result.Lines.Count | Should -Be 2
            $result.Lines[0] | Should -Be ''
            $result.Lines[1] | Should -Be ''
        }
    }

    Context 'L4 全部分支与渲染' {
        It 'Backspace 应渲染退格序列并从当前行删除字符' {
            $keys = @(
                (New-TestKey -KeyChar ([char]'a') -Key ([ConsoleKey]::A))
                (New-TestKey -KeyChar ([char]'b') -Key ([ConsoleKey]::B))
                (New-TestKey -KeyChar ([char]8) -Key ([ConsoleKey]::Backspace))
                (New-TestKey -KeyChar ([char]13) -Key ([ConsoleKey]::Enter))
                (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control)
            )

            $result = Invoke-ReaderTest -Keys $keys

            $result.Lines.Count | Should -Be 1
            $result.Lines[0] | Should -Be 'a'
            $result.RenderCalls[2].Text | Should -Be "`b `b"
            $result.RenderCalls[2].NoNewline | Should -BeTrue
        }

        It 'Delete 应渲染清行序列并使用 Prompt 长度计算覆盖范围' {
            $keys = @(
                (New-TestKey -KeyChar ([char]'a') -Key ([ConsoleKey]::A))
                (New-TestKey -KeyChar ([char]'b') -Key ([ConsoleKey]::B))
                (New-TestKey -KeyChar ([char]0) -Key ([ConsoleKey]::Delete))
                (New-TestKey -KeyChar ([char]'c') -Key ([ConsoleKey]::C))
                (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control)
            )

            $result = Invoke-ReaderTest -Keys $keys -Prompt 'P'

            $result.Lines.Count | Should -Be 1
            $result.Lines[0] | Should -Be 'c'
            # 渲染：P、a、b、清行、c；清行文本 = CR + 3 个空格 + CR + P
            $result.RenderCalls.Count | Should -Be 5
            $result.RenderCalls[3].Text | Should -Be "`r   `rP"
            $result.RenderCalls[3].NoNewline | Should -BeTrue
        }

        It '忽略按键不应产生额外渲染' {
            $keys = @(
                (New-TestKey -KeyChar ([char]0) -Key ([ConsoleKey]::LeftArrow))
                (New-TestKey -KeyChar ([char]'a') -Key ([ConsoleKey]::A))
                (New-TestKey -KeyChar ([char]13) -Key ([ConsoleKey]::Enter))
                (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control)
            )

            $result = Invoke-ReaderTest -Keys $keys

            $result.Lines.Count | Should -Be 1
            $result.Lines[0] | Should -Be 'a'
            $result.RenderCalls.Count | Should -Be 2
            $result.RenderCalls[0].Text | Should -Be 'a'
            $result.RenderCalls[1].Text | Should -Be ''
        }

        It '默认渲染器应调用 Write-Host 输出字符与换行' {
            Mock -CommandName Write-Host -ModuleName IPAP { }
            $keys = @(
                (New-TestKey -KeyChar ([char]'a') -Key ([ConsoleKey]::A))
                (New-TestKey -KeyChar ([char]13) -Key ([ConsoleKey]::Enter))
                (New-TestKey -KeyChar ([char]4) -Key ([ConsoleKey]::D) -Control)
            )

            InModuleScope IPAP -Parameters @{ KeyList = $keys } -ScriptBlock {
                param($KeyList)
                $script:DefaultRenderQueue = [System.Collections.Generic.Queue[ConsoleKeyInfo]]::new()
                foreach ($key in $KeyList) { $script:DefaultRenderQueue.Enqueue($key) }
                [scriptblock]$readKey = { return $script:DefaultRenderQueue.Dequeue() }
                Invoke-MultiLineReader -ReadKey $readKey -Prompt ''
            } | Out-Null

            # 一次 Append（NoNewline）+ 一次 NewLine
            Should -Invoke -CommandName Write-Host -ModuleName IPAP -Times 2 -Exactly
        }
    }
}
