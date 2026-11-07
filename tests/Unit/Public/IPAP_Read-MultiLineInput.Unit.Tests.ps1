#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Read-MultiLineInput 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 的 L1-L5 覆盖薄包装层：
    - L1 正常流程：Prompt 透传给 Invoke-MultiLineReader，并原样返回其行数组
    - L2 异常流程：下层抛异常时原样向上传播（本层不捕获、不改写异常）
    - L3 边界数据：内核无输出时返回空
    - L4 分支覆盖：函数体 0 分支（单行委托）；按键判定与循环分支由
      Get-MultiLineEditAction / Invoke-MultiLineReader 的单测覆盖
    - L5 输出字段：行数、逐行文本、保持原始顺序、每项为 string
    测试隔离：Mock Invoke-MultiLineReader（模块内交互协作者）定义在 BeforeEach，
    用例通过 $script:ReaderLines / $script:ReaderThrows 控制其行为。
#>

Describe 'Read-MultiLineInput Unit Tests' -Tag 'Read-MultiLineInput', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $script:ReaderLines = @()
        $script:ReaderThrows = $false

        Mock -CommandName Invoke-MultiLineReader -ModuleName IPAP {
            if ($script:ReaderThrows) {
                throw [System.InvalidOperationException]::new('无法读取控制台输入')
            }
            return $script:ReaderLines
        }
    }

    Context 'L1 正常流程' {
        It '应将 Prompt 透传给 Invoke-MultiLineReader 并返回其行数组' {
            $script:ReaderLines = @('x', 'y')

            $result = @(Read-MultiLineInput -Prompt 'p')

            $result.Count | Should -Be 2
            $result[0] | Should -Be 'x'
            $result[1] | Should -Be 'y'
            Should -Invoke -CommandName Invoke-MultiLineReader -ModuleName IPAP -ParameterFilter {
                $Prompt -eq 'p'
            } -Times 1 -Exactly
        }
    }

    Context 'L2 异常流程' {
        It '下层抛异常时应原样向上传播，不被包装或吞掉' {
            $script:ReaderThrows = $true

            { Read-MultiLineInput -Prompt 'p' } |
                Should -Throw -ExceptionType ([System.InvalidOperationException]) -ExpectedMessage '无法读取控制台输入'
        }
    }

    Context 'L3 边界数据' {
        It '内核无输出时应返回空' {
            $script:ReaderLines = @()

            $result = Read-MultiLineInput -Prompt 'p'

            $result | Should -BeNullOrEmpty
        }
    }

    # L4：函数体 0 分支（单行委托），无分支可覆盖。

    Context 'L5 输出字段' {
        It '应保持原始顺序且逐项为 string' {
            $script:ReaderLines = @('第一行', '第二行', '第三行')

            $result = @(Read-MultiLineInput -Prompt 'p')

            $result.Count | Should -Be 3
            $result[0] | Should -BeExactly '第一行'
            $result[1] | Should -BeExactly '第二行'
            $result[2] | Should -BeExactly '第三行'
            foreach ($item in $result) {
                $item | Should -BeOfType [string]
            }
        }
    }
}
