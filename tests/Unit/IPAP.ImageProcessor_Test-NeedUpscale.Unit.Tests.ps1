#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Test-NeedUpscale 单元测试
.DESCRIPTION
    测试 Test-NeedUpscale 函数的高清化判断逻辑。
#>

Describe 'Test-NeedUpscale Unit Tests' -Tag 'Test-NeedUpscale', 'IPAP.ImageProcessor' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.ImageProcessor Write-InfoLog {}
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
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

        It '$null 输入应有明确定义的行为' {
            $result = Test-NeedUpscale -AverageSize $null
            $result | Should -Be $true
        }
    }
}
