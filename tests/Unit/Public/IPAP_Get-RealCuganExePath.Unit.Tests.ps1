#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-RealCuganExePath 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五级要求覆盖 Get-RealCuganExePath：
    L1 正常流程 —— Context 'L1 正常流程'
    L2 异常流程 —— Context 'L2 异常流程'
    L3 边界数据 —— Context 'L3 边界数据'
    L4 分支覆盖 —— L1/L2 分别覆盖返回与抛出两条分支
    L5 输出字段 —— Context 'L5 输出字段'

    Write-LogEntry 在调用方测试中 Mock：本函数只负责"以 Error 级别记录完整消息后抛出"，
    日志的 5 段排版/颜色由 IPAP_Write-LogEntry.Unit.Tests.ps1 单独覆盖，
    避免调用方测试与日志格式耦合。
#>

Describe 'Get-RealCuganExePath Unit Tests' -Tag 'Get-RealCuganExePath', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 日志函数 Mock：本文件只断言"调用级别 + 消息"，不重复测试日志排版
        Mock -CommandName Write-LogEntry -ModuleName IPAP { }
    }

    Context 'L1 正常流程' {
        It '配置给出 RealCuganExePath 时返回该路径且不写日志' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ RealCuganExePath = 'C:\tools\realcugan\realcugan-ncnn-vulkan.exe' }
                }
            }

            $result = Get-RealCuganExePath

            $result | Should -Be 'C:\tools\realcugan\realcugan-ncnn-vulkan.exe'
            $result | Should -BeOfType [string]
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -Times 0 -Exactly
            Should -Invoke -CommandName Get-Configuration -ModuleName IPAP -Times 1 -Exactly
        }
    }

    Context 'L2 异常流程' {
        It '配置未给出 RealCuganExePath 时应抛出 FileNotFoundException 并记录 Error 日志' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ RealCuganExePath = '' }
                }
            }

            { Get-RealCuganExePath } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException]) -ExpectedMessage '未找到 Real-CUGAN'

            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Error' -and $Message -eq '未找到 Real-CUGAN'
            } -Times 1 -Exactly
        }
    }

    Context 'L3 边界数据' {
        It '配置值为 $null 时同样抛出 FileNotFoundException 并记录 Error 日志' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ RealCuganExePath = $null }
                }
            }

            { Get-RealCuganExePath } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException]) -ExpectedMessage '未找到 Real-CUGAN'

            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Error' -and $Message -eq '未找到 Real-CUGAN'
            } -Times 1 -Exactly
        }
    }

    Context 'L5 输出字段' {
        It '异常输出的类型、消息与日志调用字段应完整' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ RealCuganExePath = '' }
                }
            }

            $caught = $null
            try {
                Get-RealCuganExePath
            }
            catch {
                $caught = $PSItem
            }

            $caught.Exception | Should -BeOfType [System.IO.FileNotFoundException]
            $caught.Exception.Message | Should -Be '未找到 Real-CUGAN'
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Error' -and $Message -eq '未找到 Real-CUGAN'
            } -Times 1 -Exactly
        }
    }
}
