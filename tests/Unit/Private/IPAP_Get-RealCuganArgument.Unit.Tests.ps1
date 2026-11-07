#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-RealCuganArgument 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 的 L1-L5 覆盖 Real-CUGAN 参数拼装纯函数：
    - L1 正常流程：14 个参数按固定顺序逐元素断言
    - L2 异常流程：Mandatory 参数在绑定阶段拒绝空串 / 不可转换的数值，抛
      ParameterBindingException 家族；本函数无自定义校验，故不新增源码校验
    - L3 边界数据：数值边界 -1/4/32、越界值 0/99 被放行（范围校验在公共层
      Invoke-ParallelUpscale 的 ValidateRange）、纯空白模型目录不 Trim
    - L4 分支覆盖：函数体 0 分支，全部参数均为无条件的顺序拼接，无分支可测
    - L5 输出字段：元素个数与逐元素类型
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

    Context 'L2 参数绑定拒绝' {
        It 'ImagePath 为空串时应抛 ParameterBindingException 家族' {
            { InModuleScope IPAP { Get-RealCuganArgument -ImagePath '' -OutputPath 'D:\out\a.webp' -NoiseLevel 0 -Scale 2 -TileSize 128 -ModelPath 'models-se' -OutputFormat 'webp' } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*ImagePath*'
        }

        It 'Scale 为不可转换的字符串时应抛 ParameterBindingException 家族' {
            { InModuleScope IPAP { Get-RealCuganArgument -ImagePath 'C:\src\a.png' -OutputPath 'D:\out\a.webp' -NoiseLevel 0 -Scale 'abc' -TileSize 128 -ModelPath 'models-se' -OutputFormat 'webp' } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*Scale*'
        }
    }

    Context 'L3 边界数据' {
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

        It '越界的 Scale 0 与 99 应被放行（范围校验在公共层）' {
            $result = InModuleScope IPAP {
                Get-RealCuganArgument -ImagePath 'C:\a.png' -OutputPath 'D:\b.webp' `
                    -NoiseLevel 0 -Scale 99 -TileSize 128 -ModelPath 'models-se' -OutputFormat 'webp'
            }

            $result[7] | Should -Be '99'
        }

        It '模型目录为纯空白时应原样透传（不 Trim、不校验）' {
            $result = InModuleScope IPAP {
                Get-RealCuganArgument -ImagePath 'C:\a.png' -OutputPath 'D:\b.webp' `
                    -NoiseLevel 0 -Scale 2 -TileSize 128 -ModelPath '   ' -OutputFormat 'webp'
            }

            $result[11] | Should -Be '   '
        }
    }

    # L4：函数体 0 分支，全部参数按固定顺序无条件拼接，无分支可覆盖。

    Context 'L5 输出字段' {
        It '应返回 14 个元素且每个元素都是 string' {
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
