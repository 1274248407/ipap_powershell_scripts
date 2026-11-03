#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-FfmpegCodec 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 的 L1-L5 覆盖「输出格式 -> FFmpeg 编码器」纯映射：
    - L1 正常流程：jpg/jpeg/png/webp 四种格式命中映射表
    - L2 异常流程：Mandatory 字符串参数在绑定阶段拒绝空串 / $null，抛
      ParameterBindingException 家族；本函数无自定义校验
    - L3 边界数据：格式大小写不敏感
    - L4 分支覆盖：命中映射（true）由 L1 覆盖，未知回退（false）在本级
    - L5 输出字段：返回值为 string 类型
#>

Describe 'Get-FfmpegCodec Unit Tests' -Tag 'Get-FfmpegCodec', 'IPAP' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 常见格式映射' {
        It 'jpg 应映射为 mjpeg' {
            InModuleScope IPAP { Get-FfmpegCodec -OutputFormat 'jpg' } | Should -Be 'mjpeg'
        }

        It 'jpeg 应映射为 mjpeg' {
            InModuleScope IPAP { Get-FfmpegCodec -OutputFormat 'jpeg' } | Should -Be 'mjpeg'
        }

        It 'png 应映射为 png' {
            InModuleScope IPAP { Get-FfmpegCodec -OutputFormat 'png' } | Should -Be 'png'
        }

        It 'webp 应映射为 libwebp' {
            InModuleScope IPAP { Get-FfmpegCodec -OutputFormat 'webp' } | Should -Be 'libwebp'
        }
    }

    Context 'L2 参数绑定拒绝' {
        It 'OutputFormat 为空串时应抛 ParameterBindingException 家族' {
            { InModuleScope IPAP { Get-FfmpegCodec -OutputFormat '' } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*OutputFormat*'
        }

        It 'OutputFormat 为 $null 时应抛 ParameterBindingException 家族' {
            { InModuleScope IPAP { Get-FfmpegCodec -OutputFormat $null } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*OutputFormat*'
        }
    }

    Context 'L3 边界数据' {
        It '大写 JPG 也应按大小写不敏感映射为 mjpeg' {
            InModuleScope IPAP { Get-FfmpegCodec -OutputFormat 'JPG' } | Should -Be 'mjpeg'
        }
    }

    Context 'L4 分支覆盖' {
        It '未知格式应走回退分支，返回 libwebp' {
            InModuleScope IPAP { Get-FfmpegCodec -OutputFormat 'bmp' } | Should -Be 'libwebp'
        }
    }

    Context 'L5 输出字段' {
        It '返回值应为 string 类型' {
            $result = InModuleScope IPAP { Get-FfmpegCodec -OutputFormat 'png' }

            $result | Should -BeOfType [string]
        }
    }
}
