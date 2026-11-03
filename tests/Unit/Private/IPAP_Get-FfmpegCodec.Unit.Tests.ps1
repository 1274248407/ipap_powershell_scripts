#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-FfmpegCodec 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖输出格式到 FFmpeg 编码器的纯映射：
    L1 常见格式、L3 大小写与未知格式回退、L5 返回类型。
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

    Context 'L3 大小写与未知格式' {
        It '大写 JPG 也应按大小写不敏感映射为 mjpeg' {
            InModuleScope IPAP { Get-FfmpegCodec -OutputFormat 'JPG' } | Should -Be 'mjpeg'
        }

        It '未知格式应回退为 libwebp' {
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
