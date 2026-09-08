#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Test-NeedUpscale 单元测试
.DESCRIPTION
    测试 Test-NeedUpscale 函数的高清化判断逻辑。
#>

Describe 'Test-NeedUpscale Unit Tests' -Tag 'Test-NeedUpscale', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        Mock Write-LogEntry -ModuleName IPAP {}
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常判断逻辑 - Normal Logic' {
        It '平均大小小于 1000KB 应返回 $true' {
            $result = Test-NeedUpscale -AverageSize 500
            $result | Should -Be $true
        }

        It '平均大小等于 1000KB 应返回 $false' {
            $result = Test-NeedUpscale -AverageSize 1000
            $result | Should -Be $false
        }

        It '平均大小大于 1000KB 应返回 $false' {
            $result = Test-NeedUpscale -AverageSize 1500
            $result | Should -Be $false
        }
    }

    Context '边界值测试 - Boundary Value Tests' {
        It '0 KB 应返回 $true' {
            $result = Test-NeedUpscale -AverageSize 0
            $result | Should -Be $true
        }

        It '1 KB 应返回 $true' {
            $result = Test-NeedUpscale -AverageSize 1
            $result | Should -Be $true
        }

        It '999 KB 应返回 $true' {
            $result = Test-NeedUpscale -AverageSize 999
            $result | Should -Be $true
        }

        It '1001 KB 应返回 $false' {
            $result = Test-NeedUpscale -AverageSize 1001
            $result | Should -Be $false
        }

        It '极小值应返回 $true' {
            $result = Test-NeedUpscale -AverageSize 0.001
            $result | Should -Be $true
        }

        It '极大值应返回 $false' {
            $result = Test-NeedUpscale -AverageSize 1000000
            $result | Should -Be $false
        }
    }

    Context '类型验证 - Type Validation' {
        It '应接受整数输入' {
            $result = Test-NeedUpscale -AverageSize 500
            $result | Should -BeOfType [System.Boolean]
        }

        It '应接受浮点数输入' {
            $result = Test-NeedUpscale -AverageSize 500.5
            $result | Should -BeOfType [System.Boolean]
        }

        It '应接受强制类型转换' {
            $result = Test-NeedUpscale -AverageSize ([double]500)
            $result | Should -BeOfType [System.Boolean]
        }
    }

    Context '必填参数测试 - Mandatory Parameter' {
        It '函数应有 Mandatory 参数 AverageSize' {
            $cmd = Get-Command Test-NeedUpscale
            $param = $cmd.Parameters['AverageSize']
            $param.Attributes.Mandatory | Should -Be $true
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        It '应接受位置参数' {
            $result = Test-NeedUpscale 500
            $result | Should -Be $true
        }

        It '$null 输入应抛出异常' {
            { Test-NeedUpscale -AverageSize $null } | Should -Throw -ExpectedMessage '*平均文件大小不能为 null*'
        }
    }
}