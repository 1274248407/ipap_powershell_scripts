#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Write-UpscaleSummary 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 的 L1-L5 覆盖结果聚合：
    - L1 正常流程：全部成功时计数正确、逐图输出 Info 日志、不产生 Warning
    - L2 异常流程：-Results 为 $null 时由参数绑定拒绝，抛
      ParameterBindingException 家族（空数组是合法输入，见 L3）
    - L3 边界数据：空结果集返回 0/0 且不输出任何日志
    - L4 分支覆盖：成功分支（Info + SuccessCount++）与失败分支
      （Warning + FailedCount++）在同一批次内各走一次
    - L5 输出字段：字段集合固定、两个字段均为 int
#>

Describe 'Write-UpscaleSummary Unit Tests' -Tag 'Write-UpscaleSummary', 'IPAP' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -CommandName Write-LogEntry -ModuleName IPAP { }
    }

    Context 'L1 全部成功' {
        It '应统计 SuccessCount 并逐图输出 Info 日志，不输出 Warning' {
            $results = @(
                [PSCustomObject]@{ Success = $true; Image = 'a.jpg'; Error = '' }
                [PSCustomObject]@{ Success = $true; Image = 'b.jpg'; Error = '' }
                [PSCustomObject]@{ Success = $true; Image = 'c.jpg'; Error = '' }
            )

            $counts = InModuleScope IPAP -Parameters @{ R = $results } -ScriptBlock {
                param($R)
                Write-UpscaleSummary -Results $R
            }

            $counts.SuccessCount | Should -Be 3
            $counts.FailedCount | Should -Be 0
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Info' -and $Message -eq '图片处理成功: a.jpg'
            } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Info' -and $Message -eq '图片处理成功: b.jpg'
            } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Info' -and $Message -eq '图片处理成功: c.jpg'
            } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter { $Level -eq 'Warning' } -Times 0 -Exactly
        }
    }

    Context 'L2 参数绑定拒绝' {
        It 'Results 为 $null 时应抛 ParameterBindingException 家族' {
            { InModuleScope IPAP { Write-UpscaleSummary -Results $null } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*Results*'
        }
    }

    Context 'L3 空结果' {
        It '空结果应返回 0/0 且不输出日志' {
            $counts = InModuleScope IPAP -ScriptBlock {
                Write-UpscaleSummary -Results @()
            }

            $counts.SuccessCount | Should -Be 0
            $counts.FailedCount | Should -Be 0
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -Times 0 -Exactly
        }
    }

    Context 'L4 分支覆盖' {
        It '成功与失败混合时应分别走 Info / Warning 两条分支' {
            $results = @(
                [PSCustomObject]@{ Success = $true; Image = 'a.jpg'; Error = '' }
                [PSCustomObject]@{ Success = $true; Image = 'b.jpg'; Error = '' }
                [PSCustomObject]@{ Success = $false; Image = 'c.jpg'; Error = 'boom' }
            )

            $counts = InModuleScope IPAP -Parameters @{ R = $results } -ScriptBlock {
                param($R)
                Write-UpscaleSummary -Results $R
            }

            $counts.SuccessCount | Should -Be 2
            $counts.FailedCount | Should -Be 1
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Info' -and $Message -eq '图片处理成功: a.jpg'
            } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Info' -and $Message -eq '图片处理成功: b.jpg'
            } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Warning' -and $Message -eq '图片处理失败: c.jpg'
            } -Times 1 -Exactly
        }
    }

    Context 'L5 输出字段' {
        It '返回对象应包含固定的 SuccessCount / FailedCount 字段' {
            $results = @(
                [PSCustomObject]@{ Success = $true; Image = 'a.jpg'; Error = '' }
            )

            $counts = InModuleScope IPAP -Parameters @{ R = $results } -ScriptBlock {
                param($R)
                Write-UpscaleSummary -Results $R
            }

            @($counts.PSObject.Properties.Name | Sort-Object) | Should -Be @('FailedCount', 'SuccessCount')
            ($counts.SuccessCount -is [int]) | Should -BeTrue
            ($counts.FailedCount -is [int]) | Should -BeTrue
        }
    }
}
