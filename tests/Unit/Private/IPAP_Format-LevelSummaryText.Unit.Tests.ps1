#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Format-LevelSummaryText 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖分级摘要格式化：
    L1 正常摘要、L2 空集合、L3 单值/多值边界、L4 长边与 YDIF 相同/不同的分支、
    L5 返回类型与格式精确性（含 InvariantCulture 小数点）。
    该函数是纯函数，无 IO 与外部依赖。
#>

Describe 'Format-LevelSummaryText Unit Tests' -Tag 'Format-LevelSummaryText', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function New-LevelItem {
            param([int]$Level = 1, [int]$LongEdge = 1920, [double]$YDIF = 8.0)
            [PSCustomObject]@{ Level = $Level; LongEdge = $LongEdge; YDIF = $YDIF }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常摘要' {
        It '多张不同尺寸时应输出张数、长边范围与 YDIF 范围' {
            $Levels = @(
                New-LevelItem -LongEdge 2400 -YDIF 2.5
                New-LevelItem -LongEdge 3000 -YDIF 3.5
            )

            $Result = InModuleScope IPAP -Parameters @{ Items = $Levels } -ScriptBlock {
                param($Items)
                Format-LevelSummaryText -Levels $Items
            }

            $Result | Should -BeExactly '2 张，长边 2400–3000px，YDIF 2.5–3.5'
        }
    }

    Context 'L2 空集合' {
        It '空数组应返回「0 张」' {
            $Result = InModuleScope IPAP { Format-LevelSummaryText -Levels @() }

            $Result | Should -BeExactly '0 张'
        }
    }

    Context 'L3 边界数据' {
        It '单张时应只写一个长边与一个 YDIF' {
            $Levels = @(New-LevelItem -LongEdge 1920 -YDIF 8.75)

            $Result = InModuleScope IPAP -Parameters @{ Items = $Levels } -ScriptBlock {
                param($Items)
                Format-LevelSummaryText -Levels $Items
            }

            $Result | Should -BeExactly '1 张，长边 1920px，YDIF 8.75'
        }

        It '长边相同但 YDIF 不同时应只省略长边范围' {
            $Levels = @(
                New-LevelItem -LongEdge 1920 -YDIF 10.94
                New-LevelItem -LongEdge 1920 -YDIF 286.9
            )

            $Result = InModuleScope IPAP -Parameters @{ Items = $Levels } -ScriptBlock {
                param($Items)
                Format-LevelSummaryText -Levels $Items
            }

            $Result | Should -BeExactly '2 张，长边 1920px，YDIF 10.94–286.9'
        }

        It 'YDIF 整数与小数混合时应去掉多余的 .00' {
            $Levels = @(
                New-LevelItem -LongEdge 1000 -YDIF 3
                New-LevelItem -LongEdge 2000 -YDIF 3.5
            )

            $Result = InModuleScope IPAP -Parameters @{ Items = $Levels } -ScriptBlock {
                param($Items)
                Format-LevelSummaryText -Levels $Items
            }

            $Result | Should -BeExactly '2 张，长边 1000–2000px，YDIF 3–3.5'
        }
    }

    Context 'L4 分支与循环' {
        It '长边与 YDIF 都相同时不应出现连字符范围' {
            $Levels = @(
                New-LevelItem -LongEdge 800 -YDIF 2.55
                New-LevelItem -LongEdge 800 -YDIF 2.55
            )

            $Result = InModuleScope IPAP -Parameters @{ Items = $Levels } -ScriptBlock {
                param($Items)
                Format-LevelSummaryText -Levels $Items
            }

            $Result | Should -BeExactly '2 张，长边 800px，YDIF 2.55'
        }

        It '元素较多时应正确取到最小与最大值' {
            $Items = @()
            for ($i = 1; $i -le 50; $i++) { $Items += New-LevelItem -LongEdge (1000 + $i) -YDIF (1 + $i / 10) }

            $Result = InModuleScope IPAP -Parameters @{ Items = $Items } -ScriptBlock {
                param($Items)
                Format-LevelSummaryText -Levels $Items
            }

            $Result | Should -BeExactly '50 张，长边 1001–1050px，YDIF 1.1–6'
        }
    }

    Context 'L5 输出契约' {
        It '应返回单个字符串且无多余管道对象' {
            $Levels = @(New-LevelItem)

            $Result = @(InModuleScope IPAP -Parameters @{ Items = $Levels } -ScriptBlock {
                    param($Items)
                    Format-LevelSummaryText -Levels $Items
                })

            $Result.Count | Should -Be 1
            $Result[0] | Should -BeOfType [string]
        }

        It '小数点应使用 InvariantCulture 的句点而非逗号' {
            $Levels = @(
                New-LevelItem -LongEdge 1200 -YDIF 1.5
                New-LevelItem -LongEdge 1300 -YDIF 2.25
            )

            $Result = InModuleScope IPAP -Parameters @{ Items = $Levels } -ScriptBlock {
                param($Items)
                Format-LevelSummaryText -Levels $Items
            }

            $Result | Should -Match 'YDIF 1\.5–2\.25'
            $Result | Should -Not -Match 'YDIF 1,5'
        }
    }
}
