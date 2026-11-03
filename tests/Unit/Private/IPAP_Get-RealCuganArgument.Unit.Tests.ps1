#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-RealCuganArgument 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖 Real-CUGAN 参数拼装纯函数：
    L1 正常参数、L3 边界参数、L5 参数数组逐元素验证。
#>

Describe 'Get-RealCuganArgument Unit Tests' -Tag 'Get-RealCuganArgument', 'IPAP' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常参数' {
        It '应按固定顺序拼接全部参数' {
            $result = InModuleScope IPAP {
                Get-RealCuganArgument -ImagePath 'C:\src\a.png' -OutputPath 'D:\out\a.webp' `
                    -NoiseLevel 0 -Scale 2 -TileSize 128 -ModelPath 'models-se' -OutputFormat 'webp'
            }

            $expected = @(
                '-i', 'C:\src\a.png',
                '-o', 'D:\out\a.webp',
                '-n', '0',
                '-s', '2',
                '-t', '128',
                '-m', 'models-se',
                '-f', 'webp'
            )
            $result.Count | Should -Be $expected.Count
            for ($i = 0; $i -lt $expected.Count; $i++) {
                $result[$i] | Should -Be $expected[$i]
            }
        }
    }

    Context 'L3 边界参数' {
        It '应接受数值边界并转为字符串' {
            $result = InModuleScope IPAP {
                Get-RealCuganArgument -ImagePath 'C:\a.png' -OutputPath 'D:\b.jpg' `
                    -NoiseLevel -1 -Scale 4 -TileSize 32 -ModelPath 'models-pro' -OutputFormat 'jpg'
            }

            $result[5] | Should -Be '-1'
            $result[7] | Should -Be '4'
            $result[9] | Should -Be '32'
            $result[11] | Should -Be 'models-pro'
            $result[13] | Should -Be 'jpg'
        }
    }

    Context 'L5 输出字段' {
        It '返回类型应为 string[] 且每个元素都是 string' {
            $result = InModuleScope IPAP {
                Get-RealCuganArgument -ImagePath 'C:\a.png' -OutputPath 'D:\b.webp' `
                    -NoiseLevel 0 -Scale 2 -TileSize 128 -ModelPath 'models-se' -OutputFormat 'webp'
            }

            $result.Count | Should -Be 14
            foreach ($item in $result) {
                $item | Should -BeOfType [string]
            }
        }
    }
}
