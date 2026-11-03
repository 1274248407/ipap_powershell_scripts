#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Write-UpscaleSummary 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖结果聚合：
    L1 成功/失败混合、L3 空结果、L5 计数字段与日志级别。
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

    Context 'L1 成功与失败混合' {
        It '应分别统计成功/失败数并输出对应级别日志' {
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

        It '全部成功时 FailedCount 应为 0 且不输出 Warning' {
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
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter { $Level -eq 'Warning' } -Times 0 -Exactly
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
