#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Reset-Configuration 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五级要求覆盖 Reset-Configuration：
    L1 正常流程 —— 清空模块配置实例
    L2 异常流程 —— ShouldProcess 返回 false（-WhatIf）时保留实例
    L3 边界数据 —— 实例已是 $null 时调用不抛异常
    L4 分支覆盖 —— ShouldProcess 真/假两条路径
    L5 输出字段 —— [void] 输出与模块状态终值
#>

Describe 'Reset-Configuration Unit Tests' -Tag 'Reset-Configuration', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global

        function Set-ConfigSentinel {
            [CmdletBinding()]
            param([string]$Marker = 'sentinel')
            InModuleScope IPAP -Parameters @{ M = $Marker } -ScriptBlock {
                param($M)
                $script:IPAPConfigInstance = [PSCustomObject]@{ Marker = $M }
            }
        }

        function Get-ConfigState {
            [CmdletBinding()]
            param()
            InModuleScope IPAP {
                return $script:IPAPConfigInstance
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    AfterEach {
        # 测试之间不共享模块状态
        InModuleScope IPAP { $script:IPAPConfigInstance = $null }
    }

    Context 'L1 正常流程' {
        It '应清空模块配置实例' {
            Set-ConfigSentinel -Marker 'x'

            Reset-Configuration

            $state = Get-ConfigState
            $state | Should -BeNullOrEmpty
        }
    }

    Context 'L2 异常流程' {
        It '-WhatIf 时 ShouldProcess 返回 false，应保留实例' {
            Set-ConfigSentinel -Marker 'y'

            Reset-Configuration -WhatIf

            $state = Get-ConfigState
            $state | Should -Not -BeNullOrEmpty
            $state.Marker | Should -Be 'y'
        }
    }

    Context 'L3 边界数据' {
        It '实例已经是 $null 时应正常返回而不抛异常' {
            InModuleScope IPAP { $script:IPAPConfigInstance = $null }

            { Reset-Configuration } | Should -Not -Throw

            $state = Get-ConfigState
            $state | Should -BeNullOrEmpty
        }
    }

    Context 'L4 分支覆盖' {
        It '-Confirm:$false 时 ShouldProcess 返回 true，应清空实例' {
            Set-ConfigSentinel -Marker 'z'

            Reset-Configuration -Confirm:$false

            $state = Get-ConfigState
            $state | Should -BeNullOrEmpty
        }
    }

    Context 'L5 输出字段' {
        It '函数应无任何输出且模块状态终值为 $null' {
            Set-ConfigSentinel -Marker 'w'

            $result = Reset-Configuration

            $result | Should -BeNullOrEmpty
            $state = Get-ConfigState
            $state | Should -BeNullOrEmpty
        }
    }
}
