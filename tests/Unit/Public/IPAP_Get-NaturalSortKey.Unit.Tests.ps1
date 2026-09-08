#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-NaturalSortKey 单元测试
.DESCRIPTION
    测试 Get-NaturalSortKey 函数的边界情况、输出验证和自然排序语义。
    该函数返回零填充的字符串，确保数字按数值大小排序。
    例如 "file10.txt" -> "file0000000010.txt"
#>

Describe 'Get-NaturalSortKey Unit Tests' -Tag 'Get-NaturalSortKey', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution Path' {
        It '应正确解析包含数字的字符串' {
            $result = Get-NaturalSortKey -InputString 'file10.txt'
            $result | Should -Be 'file0000000010.txt'
        }

        It '应正确解析纯数字字符串' {
            $result = Get-NaturalSortKey -InputString '123'
            $result | Should -Be '0000000123'
        }

        It '应正确解析包含多个数字的字符串' {
            $result = Get-NaturalSortKey -InputString 'file10_part20_final'
            $result | Should -Be 'file0000000010_part0000000020_final'
        }

        It '应正确处理文件名中的数字' {
            $result = Get-NaturalSortKey -InputString 'image100.jpg'
            $result | Should -Be 'image0000000100.jpg'
        }
    }

    Context '边界值测试 - Boundary Value Tests' {
        It '应处理只包含数字的字符串' {
            $result = Get-NaturalSortKey -InputString '42'
            $result | Should -Be '0000000042'
        }

        It '应处理包含特殊字符的字符串' {
            $result = Get-NaturalSortKey -InputString 'file@#$%10'
            $result | Should -Be 'file@#$%0000000010'
        }

        It '应处理超长字符串' {
            $longString = 'a' * 100 + '123' + 'b' * 100
            $result = Get-NaturalSortKey -InputString $longString
            $result | Should -Be (('a' * 100) + '0000000123' + ('b' * 100))
        }

        It '应处理带空格的文件名' {
            $result = Get-NaturalSortKey -InputString 'my file 10.txt'
            $result | Should -Be 'my file 0000000010.txt'
        }

        It '应处理带括号的文件名' {
            $result = Get-NaturalSortKey -InputString 'image (1).jpg'
            $result | Should -Be 'image (0000000001).jpg'
        }

        It '应处理带连字符的文件名' {
            $result = Get-NaturalSortKey -InputString 'file-name-10-final.txt'
            $result | Should -Be 'file-name-0000000010-final.txt'
        }

        It '应处理带下划线的文件名' {
            $result = Get-NaturalSortKey -InputString 'file_name_10_final.txt'
            $result | Should -Be 'file_name_0000000010_final.txt'
        }

        It '应处理带中文的字符串' {
            $result = Get-NaturalSortKey -InputString '文件10测试'
            $result | Should -Be '文件0000000010测试'
        }
    }

    Context '类型验证 - Type Validation' {
        It '返回类型应为字符串' {
            $result = Get-NaturalSortKey -InputString 'test123'
            $result | Should -BeOfType [string]
        }
    }

    Context '自然排序语义验证 - Natural Sort Semantics' {
        It '应正确处理前导零' {
            $result = Get-NaturalSortKey -InputString 'file007.txt'
            $result | Should -Be 'file0000000007.txt'
        }

        It '应处理混合数字和字母' {
            $result = Get-NaturalSortKey -InputString 'a1b2c3'
            $result | Should -Be 'a0000000001b0000000002c0000000003'
        }

        It '自然排序应正确排序' {
            $files = @('10.webp', '11.webp', '02.webp', '03.webp', '04.webp', '05.webp', '06.webp', '07.webp', '08.webp', '09.webp')
            $sorted = $files | Sort-Object -Property { Get-NaturalSortKey $PSItem }
            $sorted[0] | Should -Be '02.webp'
            $sorted[1] | Should -Be '03.webp'
            $sorted[8] | Should -Be '10.webp'
            $sorted[9] | Should -Be '11.webp'
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        It '函数应有 Mandatory 参数 InputString' {
            $cmd = Get-Command Get-NaturalSortKey
            $inputStringParam = $cmd.Parameters['InputString']
            $inputStringParam.Attributes.Mandatory | Should -Be $true
        }

        It '应声明 OutputType 为 string' {
            $cmd = Get-Command Get-NaturalSortKey
            $outputType = $cmd.OutputType
            $outputType.Type.Name | Should -Contain 'String'
        }
    }
}
