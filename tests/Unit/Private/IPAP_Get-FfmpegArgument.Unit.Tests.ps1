#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-FfmpegArgument 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖 FFmpeg 参数拼装纯函数：
    L1 三种格式、L5 参数数组逐元素与编码器注入验证。
#>

Describe 'Get-FfmpegArgument Unit Tests' -Tag 'Get-FfmpegArgument', 'IPAP' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 正常参数' {
        It 'webp 输出应使用 libwebp 编码器并保持滤镜链固定' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\src\a.png' -OutputPath 'D:\out\a.webp' -OutputFormat 'webp'
            }

            $expected = @(
                '-i', 'C:\src\a.png',
                '-vf', 'scale=iw*1.2:ih*1.2:flags=lanczos,unsharp=5:5:1.0',
                '-c:v', 'libwebp',
                '-quality', '95',
                '-y', 'D:\out\a.webp'
            )
            $result.Count | Should -Be $expected.Count
            for ($i = 0; $i -lt $expected.Count; $i++) {
                $result[$i] | Should -Be $expected[$i]
            }
        }

        It 'jpg 输出应使用 mjpeg 编码器' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\src\a.png' -OutputPath 'D:\out\a.jpg' -OutputFormat 'jpg'
            }

            $result[5] | Should -Be 'mjpeg'
            $result[9] | Should -Be 'D:\out\a.jpg'
        }

        It 'png 输出应使用 png 编码器' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\src\a.png' -OutputPath 'D:\out\a.png' -OutputFormat 'png'
            }

            $result[5] | Should -Be 'png'
        }
    }

    Context 'L5 输出字段' {
        It '返回类型应为 string[] 且每个元素都是 string' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\a.png' -OutputPath 'D:\b.webp' -OutputFormat 'webp'
            }

            $result.Count | Should -Be 10
            foreach ($item in $result) {
                $item | Should -BeOfType [string]
            }
        }
    }
}
