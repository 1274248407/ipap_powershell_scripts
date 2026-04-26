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
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'

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
            $result = Get-NaturalSortKey -String 'file10.txt'
            $result.Count | Should -BeGreaterThan 1
            $result[0] | Should -Be 'file'
            $result[1] | Should -Be 10
            $result[2] | Should -Be '.txt'
        }

        It '应正确解析纯数字字符串' {
            $result = Get-NaturalSortKey -String '123'
            $result.Count | Should -Be 1
            $result[0] | Should -Be 123
        }

        It '应正确解析包含多个数字的字符串' {
            $result = Get-NaturalSortKey -String 'file10_part20_final'
            $result.Count | Should -BeGreaterThan 1
        }

        It '应正确处理文件名中的数字' {
            $result = Get-NaturalSortKey -String 'image100.jpg'
            $result[0] | Should -Be 'image'
            $result[1] | Should -Be 100
            $result[2] | Should -Be '.jpg'
        }
    }

    Context '边界值测试 - Boundary Value Tests' {
        It '应处理只包含数字的字符串' {
            $result = Get-NaturalSortKey -String '42'
            $result.Count | Should -Be 1
            $result[0] | Should -Be 42
        }

        It '应处理包含特殊字符的字符串' {
            $result = Get-NaturalSortKey -String 'file@#$%10'
            $result.Count | Should -BeGreaterThan 1
        }

        It '应处理超长字符串' {
            $longString = 'a' * 100 + '123' + 'b' * 100
            $result = Get-NaturalSortKey -String $longString
            $result.Count | Should -BeGreaterThan 0
        }

        It '应处理带空格的文件名' {
            $result = Get-NaturalSortKey -String 'my file 10.txt'
            $result | Should -Not -BeNullOrEmpty
        }

        It '应处理带括号的文件名' {
            $result = Get-NaturalSortKey -String 'image (1).jpg'
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 1
        }

        It '应处理带连字符的文件名' {
            $result = Get-NaturalSortKey -String 'file-name-10-final.txt'
            $result | Should -Not -BeNullOrEmpty
        }

        It '应处理带下划线的文件名' {
            $result = Get-NaturalSortKey -String 'file_name_10_final.txt'
            $result | Should -Not -BeNullOrEmpty
        }

        It '应处理带中文的字符串' {
            $result = Get-NaturalSortKey -String '文件10测试'
            $result.Count | Should -BeGreaterThan 0
        }
    }

    Context '类型验证 - Type Validation' {
        It '返回类型应为数组' {
            $result = Get-NaturalSortKey -String 'test123'
            $result | Should -BeOfType [System.Array]
        }

        It '数字部分应为整数类型' {
            $result = Get-NaturalSortKey -String 'file10.txt'
            $numericParts = $result | Where-Object { $_ -is [int] }
            $numericParts | Should -Not -BeNullOrEmpty
            $numericParts[0] | Should -BeOfType [System.Int32]
        }

        It '字符串部分应为字符串类型' {
            $result = Get-NaturalSortKey -String 'file10.txt'
            $stringParts = $result | Where-Object { $_ -is [string] }
            $stringParts | Should -Not -BeNullOrEmpty
            $stringParts[0] | Should -BeOfType [System.String]
        }
    }

    Context '自然排序语义验证 - Natural Sort Semantics' {
        It '应正确处理前导零' {
            $result = Get-NaturalSortKey -String 'file007.txt'
            $numericParts = $result | Where-Object { $_ -is [int] }
            $numericParts[0] | Should -Be 7
        }

        It '应处理混合数字和字母' {
            $result = Get-NaturalSortKey -String 'a1b2c3'
            $result.Count | Should -BeGreaterThan 1
        }

        It '应能用于自然排序比较' {
            $items = @('file2.txt', 'file10.txt', 'file1.txt')
            $sortedKeys = $items | ForEach-Object { Get-NaturalSortKey -String $PSItem }
            $sortedKeys[0][0] | Should -Be 'file'
            $sortedKeys[1][0] | Should -Be 'file'
            $sortedKeys[2][0] | Should -Be 'file'
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        It '必填参数 String 缺失时应报错' {
            { Get-NaturalSortKey } | Should -Throw
        }

        It '应接受管道输入' {
            $result = 'test123' | Get-NaturalSortKey
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }
    }
}
