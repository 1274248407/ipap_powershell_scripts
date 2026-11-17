#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Format-ProjectLevelText 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖项目等级文案格式化：
    L1 三档正常文案、L2 ValidateRange 拒绝、L3 边界（1/4 倍）、
    L4 分支（RealCuganScale 只影响 Level 2）、L5 返回类型与单值输出。
    该函数是纯函数，无 IO 与外部依赖。
#>

Describe 'Format-ProjectLevelText Unit Tests' -Tag 'Format-ProjectLevelText', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常文案' {
        It 'Level 0 应说明「不放大」' {
            $Result = InModuleScope IPAP { Format-ProjectLevelText -Level 0 }

            $Result | Should -BeExactly 'Level 0（已高清，不放大）'
        }

        It 'Level 1 应说明 FFmpeg 1.2 倍放大 + 锐化' {
            $Result = InModuleScope IPAP { Format-ProjectLevelText -Level 1 }

            $Result | Should -BeExactly 'Level 1（FFmpeg 1.2 倍放大 + 锐化）'
        }

        It 'Level 2 应说明 Real-CUGAN 超分与默认 2 倍' {
            $Result = InModuleScope IPAP { Format-ProjectLevelText -Level 2 }

            $Result | Should -BeExactly 'Level 2（Real-CUGAN 2 倍超分）'
        }
    }

    Context 'L2 异常输入' {
        It 'Level 为 -1 时应被 ValidateRange 拒绝' {
            { InModuleScope IPAP { Format-ProjectLevelText -Level -1 } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'Level 为 3 时应被 ValidateRange 拒绝' {
            { InModuleScope IPAP { Format-ProjectLevelText -Level 3 } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'RealCuganScale 为 0 时应被 ValidateRange 拒绝' {
            { InModuleScope IPAP { Format-ProjectLevelText -Level 2 -RealCuganScale 0 } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }
    }

    Context 'L3 边界数据' {
        It 'RealCuganScale 取上界 4 时应写入 4 倍' {
            $Result = InModuleScope IPAP { Format-ProjectLevelText -Level 2 -RealCuganScale 4 }

            $Result | Should -BeExactly 'Level 2（Real-CUGAN 4 倍超分）'
        }

        It 'RealCuganScale 取下界 1 时应写入 1 倍' {
            $Result = InModuleScope IPAP { Format-ProjectLevelText -Level 2 -RealCuganScale 1 }

            $Result | Should -BeExactly 'Level 2（Real-CUGAN 1 倍超分）'
        }
    }

    Context 'L4 分支与参数隔离' {
        It 'RealCuganScale 不应影响 Level 0 的文案' {
            $Result = InModuleScope IPAP { Format-ProjectLevelText -Level 0 -RealCuganScale 4 }

            $Result | Should -BeExactly 'Level 0（已高清，不放大）'
        }

        It 'RealCuganScale 不应影响 Level 1 的文案' {
            $Result = InModuleScope IPAP { Format-ProjectLevelText -Level 1 -RealCuganScale 4 }

            $Result | Should -BeExactly 'Level 1（FFmpeg 1.2 倍放大 + 锐化）'
        }
    }

    Context 'L5 输出契约' {
        It '应返回单个字符串且无多余管道对象' {
            $Result = @(InModuleScope IPAP { Format-ProjectLevelText -Level 1 })

            $Result.Count | Should -Be 1
            $Result[0] | Should -BeOfType [string]
        }
    }
}
