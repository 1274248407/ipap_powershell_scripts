#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Core - Get-NaturalSortKey 单元测试
.DESCRIPTION
    测试 Get-NaturalSortKey 函数的边界情况、输出验证和管道行为。
    注意：Get-NaturalSortKey 使用 [regex]::Split($String, '([0-9]+)') 实现，
    会按数字分割字符串，返回数组。例如 "file10.txt" -> ["file", "10", ".txt"]
#>

Describe 'Get-NaturalSortKey Unit Tests' -Tag 'Get-NaturalSortKey', 'IPAP.Core' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psd1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force
        }
    }

    AfterAll {
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution Path' {
        It '应正确解析包含数字的字符串' {
            $result = Get-NaturalSortKey -InputString 'file10.txt'
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'file'
            $result[1] | Should -Be 10
            $result[2] | Should -Be '.txt'
        }

        It '应正确解析纯数字字符串' {
            $result = Get-NaturalSortKey -InputString '123'
            $result.Count | Should -Be 1
            $result[0] | Should -Be 123
        }

        It '应正确解析包含多个数字的字符串' {
            $result = Get-NaturalSortKey -InputString 'file10_part20_final'
            $result.Count | Should -Be 5
            $result[0] | Should -Be 'file'
            $result[1] | Should -Be 10
            $result[2] | Should -Be '_part'
            $result[3] | Should -Be 20
            $result[4] | Should -Be '_final'
        }

        It '应正确处理文件名中的数字' {
            $result = Get-NaturalSortKey -InputString 'image100.jpg'
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'image'
            $result[1] | Should -Be 100
            $result[2] | Should -Be '.jpg'
        }
    }

    Context '边界值测试 - Boundary Value Tests' {
        It '应处理只包含数字的字符串' {
            $result = Get-NaturalSortKey -InputString '42'
            $result.Count | Should -Be 1
            $result[0] | Should -Be 42
        }

        It '应处理包含特殊字符的字符串' {
            $result = Get-NaturalSortKey -InputString 'file@#$%10'
            $result.Count | Should -Be 2
            $result[0] | Should -Be 'file@#$%'
            $result[1] | Should -Be 10
        }

        It '应处理超长字符串' {
            $longString = 'a' * 100 + '123' + 'b' * 100
            $result = Get-NaturalSortKey -InputString $longString
            $result.Count | Should -Be 3
            $result[0] | Should -Be ('a' * 100)
            $result[1] | Should -Be 123
            $result[2] | Should -Be ('b' * 100)
        }

        It '应处理带空格的文件名' {
            $result = Get-NaturalSortKey -InputString 'my file 10.txt'
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'my file '
            $result[1] | Should -Be 10
            $result[2] | Should -Be '.txt'
        }

        It '应处理带括号的文件名' {
            $result = Get-NaturalSortKey -InputString 'image (1).jpg'
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'image ('
            $result[1] | Should -Be 1
            $result[2] | Should -Be ').jpg'
        }

        It '应处理带连字符的文件名' {
            $result = Get-NaturalSortKey -InputString 'file-name-10-final.txt'
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'file-name-'
            $result[1] | Should -Be 10
            $result[2] | Should -Be '-final.txt'
        }

        It '应处理带下划线的文件名' {
            $result = Get-NaturalSortKey -InputString 'file_name_10_final.txt'
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'file_name_'
            $result[1] | Should -Be 10
            $result[2] | Should -Be '_final.txt'
        }

        It '应处理带中文的字符串' {
            $result = Get-NaturalSortKey -InputString '文件10测试'
            $result.Count | Should -Be 3
            $result[0] | Should -Be '文件'
            $result[1] | Should -Be 10
            $result[2] | Should -Be '测试'
        }
    }

    Context '类型验证 - Type Validation' {
        It '返回类型应为数组' {
            $result = Get-NaturalSortKey -InputString 'test123'
            # 当你使用 $result | Should -BeOfType [array] 时，如果 $result 是数组，
            # 管道会自动展开数组 ，将每个元素逐个传递给 Should 断言。
            # 因此 Should 收到的是数组的第一个元素 'test' （字符串类型），而不是整个数组对象。
            # 使用逗号运算符 , 来强制将数组作为单个对象传递：
            , $result | Should -BeOfType [array]
        }

        It '数字部分应为整数类型' {
            $result = Get-NaturalSortKey -InputString 'file10.txt'
            $numericParts = $result | Where-Object { $PSItem -is [int] }
            $numericParts | Should -Not -BeNullOrEmpty
            $numericParts[0] | Should -BeOfType [int]
        }

        It '字符串部分应为字符串类型' {
            $result = Get-NaturalSortKey -InputString 'file10.txt'
            $stringParts = $result | Where-Object { $PSItem -is [string] }
            $stringParts | Should -Not -BeNullOrEmpty
            $stringParts[0] | Should -BeOfType [string]
        }
    }

    Context '自然排序语义验证 - Natural Sort Semantics' {
        It '应正确处理前导零' {
            $result = Get-NaturalSortKey -InputString 'file007.txt'
            $numericParts = $result | Where-Object { $PSItem -is [int] }
            $numericParts[0] | Should -Be 7
        }

        It '应处理混合数字和字母' {
            $result = Get-NaturalSortKey -InputString 'a1b2c3'
            $result.Count | Should -Be 6
            $result[0] | Should -Be 'a'
            $result[1] | Should -Be 1
            $result[2] | Should -Be 'b'
            $result[3] | Should -Be 2
            $result[4] | Should -Be 'c'
            $result[5] | Should -Be 3
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        It '函数应有 Mandatory 参数 InputString' {
            $cmd = Get-Command Get-NaturalSortKey
            $inputStringParam = $cmd.Parameters['InputString']
            $inputStringParam.Attributes.Mandatory | Should -Be $true
        }
    }
}
