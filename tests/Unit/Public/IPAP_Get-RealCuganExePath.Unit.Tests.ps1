#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-RealCuganExePath 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五级要求覆盖 Get-RealCuganExePath：
    L1 正常流程 —— Context 'L1 正常流程'
    L2 异常流程 —— Context 'L2 异常流程'
    L3 边界数据 —— Context 'L3 边界数据'
    L4 分支覆盖 —— L1/L2 分别覆盖返回与抛出两条分支，L2 验证日志先于异常
    L5 输出字段 —— Context 'L5 输出字段'

    Write-LogEntry 不设 Mock，走真实实现；Mock Write-Host 捕获 5 段输出，
    以钉住「ERROR 日志先完整写出，再由显式 throw 抛强类型异常」。
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
        # Mock Write-Host 记录每段调用参数，供日志内容与顺序断言使用
        $script:WriteHostCalls = @()
        Mock -CommandName Write-Host -ModuleName IPAP {
            param($Object, $NoNewline, $ForegroundColor, $BackgroundColor)
            $script:WriteHostCalls += [pscustomobject]@{
                Text            = [string]::Join('', @($Object))
                NoNewline       = $NoNewline
                ForegroundColor = [string]$ForegroundColor
                BackgroundColor = [string]$BackgroundColor
            }
        }
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
            $script:WriteHostCalls.Count | Should -Be 0
            Should -Invoke -CommandName Get-Configuration -ModuleName IPAP -Times 1 -Exactly
        }
    }

    Context 'L2 异常流程' {
        It '配置未给出 RealCuganExePath 时应抛出 FileNotFoundException 并先记录 ERROR 日志' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ RealCuganExePath = '' }
                }
            }

            { Get-RealCuganExePath } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException]) -ExpectedMessage '未找到 Real-CUGAN'

            $script:WriteHostCalls.Count | Should -Be 5
            $script:WriteHostCalls[1].Text | Should -Be '| ERROR   | '
            $script:WriteHostCalls[3].Text | Should -Be '未找到 Real-CUGAN'
            $script:WriteHostCalls[3].BackgroundColor | Should -Be 'Red'
        }
    }

    Context 'L3 边界数据' {
        It '配置值为 $null 时同样抛出 FileNotFoundException' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ RealCuganExePath = $null }
                }
            }

            { Get-RealCuganExePath } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException]) -ExpectedMessage '未找到 Real-CUGAN'

            $script:WriteHostCalls.Count | Should -Be 5
        }
    }

    Context 'L5 输出字段' {
        It '异常输出的类型、消息与日志字段应完整' {
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
            $script:WriteHostCalls.Count | Should -Be 5
            $script:WriteHostCalls[1].Text | Should -Be '| ERROR   | '
            $script:WriteHostCalls[3].Text | Should -Be '未找到 Real-CUGAN'
            $script:WriteHostCalls[3].ForegroundColor | Should -Be 'White'
            $script:WriteHostCalls[3].BackgroundColor | Should -Be 'Red'
        }
    }
}
