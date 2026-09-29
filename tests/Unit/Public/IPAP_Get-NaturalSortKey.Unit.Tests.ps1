#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-NaturalSortKey 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五级要求编写，测试 Get-NaturalSortKey 纯函数
    （正则分割数字 + 10 位零填充拼接）的输入输出契约：
    - Level1 正常流程：含数字字符串、纯数字、多数字、文件名数字
    - Level2 异常流程：本函数无自定义逻辑异常分支，空字符串与 $null 输入由
      引擎 Mandatory 参数校验拦截（ParameterBindingValidationException，
      函数体不进入），以类型级断言承载
    - Level3 边界数据：特殊字符、超长字符串、空格/括号/连字符/下划线/中文、
      全空白输入原样透传、数字仅位于字符串开头、负数（负号保留）
    - Level4 分支覆盖：数字分支（PadLeft 零填充）/ 非数字分支（原样透传）、
      正则分割两端空串元素过滤（'123' 覆盖）、自然排序组合验证（Sort-Object
      配合真实调用，逐位断言）
    - Level5 输出字段：返回类型为 string、零填充后值逐字段精确断言

    既定契约说明（Q2=A 决策：本次不改源码，仅记录）：
    - 零填充宽度固定为 10 位（PadLeft(10)）。数字位数超过 10 时不截断、
      原样返回，此时排序语义退化（11+ 位数字按字典序比较而非数值序）。
      图片文件名中的数字在实际业务域内不会超过 10 位，风险趋近于零；
      故不对该场景构造用例，亦不修改源码，此上限视为函数既定契约。

.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
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

    Context '正常执行路径 - L1 正常流程' {
        It '应正确解析包含数字的字符串' {
            $Result = Get-NaturalSortKey -InputString 'file10.txt'
            $Result | Should -Be 'file0000000010.txt'
        }

        It '应正确解析纯数字字符串' {
            $Result = Get-NaturalSortKey -InputString '123'
            $Result | Should -Be '0000000123'
        }

        It '应正确解析包含多个数字的字符串' {
            $Result = Get-NaturalSortKey -InputString 'file10_part20_final'
            $Result | Should -Be 'file0000000010_part0000000020_final'
        }

        It '应正确处理文件名中的数字' {
            $Result = Get-NaturalSortKey -InputString 'image100.jpg'
            $Result | Should -Be 'image0000000100.jpg'
        }
    }

    Context '异常与参数契约 - L2 异常流程' {
        # L2 说明：本函数为纯函数，无自定义逻辑异常分支（无守卫、无 IO）；
        # 空字符串与 $null 输入在参数绑定阶段即被引擎 Mandatory 校验拦截
        #（ParameterBindingValidationException，函数体不进入），以动态调用
        # + 类型级断言承载 L2。-ExceptionType 使用公共父类型 ParameterBindingException
        #（子类型字面量 ParameterBindingValidationException 在 Pester 作用域内无法解析）。
        It 'InputString 为空字符串时应由引擎绑定校验拦截' {
            { Get-NaturalSortKey -InputString '' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*InputString*'
        }

        It 'InputString 为 $null 时应由引擎绑定校验拦截' {
            { Get-NaturalSortKey -InputString $null } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*InputString*'
        }
    }

    Context '边界值测试 - L3 边界' {
        It '应处理只包含数字的字符串' {
            $Result = Get-NaturalSortKey -InputString '42'
            $Result | Should -Be '0000000042'
        }

        It '应处理包含特殊字符的字符串' {
            $Result = Get-NaturalSortKey -InputString 'file@#$%10'
            $Result | Should -Be 'file@#$%0000000010'
        }

        It '应处理超长字符串' {
            $LongString = 'a' * 100 + '123' + 'b' * 100
            $Result = Get-NaturalSortKey -InputString $LongString
            $Result | Should -Be (('a' * 100) + '0000000123' + ('b' * 100))
        }

        It '应处理带空格的文件名' {
            $Result = Get-NaturalSortKey -InputString 'my file 10.txt'
            $Result | Should -Be 'my file 0000000010.txt'
        }

        It '应处理带括号的文件名' {
            $Result = Get-NaturalSortKey -InputString 'image (1).jpg'
            $Result | Should -Be 'image (0000000001).jpg'
        }

        It '应处理带连字符的文件名' {
            $Result = Get-NaturalSortKey -InputString 'file-name-10-final.txt'
            $Result | Should -Be 'file-name-0000000010-final.txt'
        }

        It '应处理带下划线的文件名' {
            $Result = Get-NaturalSortKey -InputString 'file_name_10_final.txt'
            $Result | Should -Be 'file_name_0000000010_final.txt'
        }

        It '应处理带中文的字符串' {
            $Result = Get-NaturalSortKey -InputString '文件10测试'
            $Result | Should -Be '文件0000000010测试'
        }

        It '全空白输入应原样返回（不触发引擎校验）' {
            $Result = Get-NaturalSortKey -InputString '   '
            $Result | Should -Be '   '
        }

        It '数字仅位于字符串开头时应正确零填充' {
            $Result = Get-NaturalSortKey -InputString '10abc'
            $Result | Should -Be '0000000010abc'
        }

        It '负数输入应保留负号并对数字零填充' {
            $Result = Get-NaturalSortKey -InputString '-10'
            $Result | Should -Be '-0000000010'
        }
    }

    Context '类型验证 - L5 输出字段' {
        It '返回类型应为字符串' {
            $Result = Get-NaturalSortKey -InputString 'test123'
            $Result | Should -BeOfType [string]
        }
    }

    Context '自然排序语义验证 - L4/L5 排序契约' {
        It '应正确处理前导零' {
            $Result = Get-NaturalSortKey -InputString 'file007.txt'
            $Result | Should -Be 'file0000000007.txt'
        }

        It '应处理混合数字和字母' {
            $Result = Get-NaturalSortKey -InputString 'a1b2c3'
            $Result | Should -Be 'a0000000001b0000000002c0000000003'
        }

        It '自然排序应正确排序（逐位断言全部元素）' {
            $Files = @('10.webp', '11.webp', '02.webp', '03.webp', '04.webp', '05.webp', '06.webp', '07.webp', '08.webp', '09.webp')
            $Sorted = $Files | Sort-Object -Property { Get-NaturalSortKey $PSItem }
            # 10 个元素逐位验证，确保自然序 02 → 03 → ... → 10 → 11
            $Sorted[0] | Should -Be '02.webp'
            $Sorted[1] | Should -Be '03.webp'
            $Sorted[2] | Should -Be '04.webp'
            $Sorted[3] | Should -Be '05.webp'
            $Sorted[4] | Should -Be '06.webp'
            $Sorted[5] | Should -Be '07.webp'
            $Sorted[6] | Should -Be '08.webp'
            $Sorted[7] | Should -Be '09.webp'
            $Sorted[8] | Should -Be '10.webp'
            $Sorted[9] | Should -Be '11.webp'
        }
    }

    Context '参数绑定契约 - 契约验证' {
        It '函数应有 Mandatory 参数 InputString' {
            $Cmd = Get-Command Get-NaturalSortKey
            $InputStringParam = $Cmd.Parameters['InputString']
            $InputStringParam.Attributes.Mandatory | Should -Be $true
        }

        It '应声明 OutputType 为 string' {
            $Cmd = Get-Command Get-NaturalSortKey
            $OutputType = $Cmd.OutputType
            @($OutputType.Type.Name) | Should -Contain 'String'
        }
    }
}