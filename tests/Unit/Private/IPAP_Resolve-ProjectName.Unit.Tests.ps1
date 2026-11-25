#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Resolve-ProjectName 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖项目命名：
    L1 两个值都给、L2 缺项时交互补齐、L3 空白裁剪、L4 两个都空、L5 返回字符串。
    Read-TrimmedInput 是交互 IO，全部 Mock。
#>

Describe 'Resolve-ProjectName Unit Tests' -Tag 'Resolve-ProjectName', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function Resolve-Name {
            param ([string]$Author = '', [string]$Title = '')
            return InModuleScope IPAP -Parameters @{ A = $Author; T = $Title } -ScriptBlock {
                param($A, $T)
                Resolve-ProjectName -Author $A -OriginalTitle $T
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock Write-LogEntry -ModuleName IPAP { }
        Mock Read-TrimmedInput -ModuleName IPAP { return '补录值' }
    }

    Context 'L1 正常路径' {
        It '两个值都给时应拼成 [作者] 标题' {
            Resolve-Name -Author '某作者' -Title '某作品' | Should -BeExactly '[某作者] 某作品'
        }

        It '已有值时不应触发交互输入' {
            $null = Resolve-Name -Author '某作者' -Title '某作品'

            Should -Invoke -ModuleName IPAP Read-TrimmedInput -Times 0 -Exactly
        }
    }

    Context 'L2 缺项时交互补齐' {
        It '作者为空时应提示补录作者名' {
            Resolve-Name -Author '' -Title '某作品' | Should -BeExactly '[补录值] 某作品'

            Should -Invoke -ModuleName IPAP Read-TrimmedInput -Times 1 -Exactly `
                -ParameterFilter { $Prompt -eq '作者名' }
        }

        It '原文为空时应提示补录原作品名' {
            Resolve-Name -Author '某作者' -Title '' | Should -BeExactly '[某作者] 补录值'

            Should -Invoke -ModuleName IPAP Read-TrimmedInput -Times 1 -Exactly `
                -ParameterFilter { $Prompt -like '原作品名*' }
        }
    }

    Context 'L3 空白裁剪' {
        It '前后空白应被裁掉' {
            Resolve-Name -Author '  某作者  ' -Title '  某作品  ' | Should -BeExactly '[某作者] 某作品'
        }

        It '纯空白应视为未提供并触发交互' {
            $null = Resolve-Name -Author '   ' -Title '   '

            Should -Invoke -ModuleName IPAP Read-TrimmedInput -Times 2 -Exactly
        }
    }

    Context 'L4 两个都空' {
        It '两个都空时应连续补录两次' {
            Resolve-Name | Should -BeExactly '[补录值] 补录值'

            Should -Invoke -ModuleName IPAP Read-TrimmedInput -Times 2 -Exactly
        }
    }

    Context 'L5 输出契约' {
        It '应返回单个字符串' {
            $Result = Resolve-Name -Author 'A' -Title 'T'

            $Result | Should -BeOfType ([string])
            , $Result | Should -HaveCount 1
        }
    }
}
