#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-FfmpegArgument 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 的 L1-L5 覆盖 FFmpeg 参数拼装纯函数：
    - L1 正常流程：webp/jpg/png 三种输出格式的完整参数数组逐元素断言
    - L2 异常流程：Mandatory 字符串参数在绑定阶段拒绝 $null / 空串，抛
      ParameterBindingException 家族；本函数无自定义校验，故不新增源码校验
    - L3 边界数据：纯空白路径原样透传（不 Trim、不校验）、格式大小写不敏感、
      未知格式回退 libwebp、中文与空格路径保真
    - L4 分支覆盖：函数体 0 分支；唯一分支是 Get-FfmpegCodec 的编码器回退，
      已在其 L4 用例覆盖，本文件不造重复用例
    - L5 输出字段：元素个数与逐元素类型，并钉住运行时数组类型为 Object[]
      （函数输出经管道展开，[OutputType([string])] 声明的是元素类型）
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

    Context 'L2 参数绑定拒绝' {
        It 'ImagePath 为空串时应抛 ParameterBindingException 家族' {
            { InModuleScope IPAP { Get-FfmpegArgument -ImagePath '' -OutputPath 'D:\out\a.webp' -OutputFormat 'webp' } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*ImagePath*'
        }

        It 'OutputPath 为 $null 时应抛 ParameterBindingException 家族' {
            { InModuleScope IPAP { Get-FfmpegArgument -ImagePath 'C:\src\a.png' -OutputPath $null -OutputFormat 'webp' } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*OutputPath*'
        }

        It 'OutputFormat 为空串时应抛 ParameterBindingException 家族' {
            { InModuleScope IPAP { Get-FfmpegArgument -ImagePath 'C:\src\a.png' -OutputPath 'D:\out\a.webp' -OutputFormat '' } } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*OutputFormat*'
        }
    }

    Context 'L3 边界数据' {
        It 'ImagePath 为纯空白时应原样透传（不 Trim、不校验）' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath '   ' -OutputPath 'D:\out\a.webp' -OutputFormat 'webp'
            }

            $result[1] | Should -Be '   '
        }

        It 'OutputPath 为纯空白时应原样透传（不 Trim、不校验）' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\src\a.png' -OutputPath '   ' -OutputFormat 'webp'
            }

            $result[9] | Should -Be '   '
        }

        It '格式为大写时应按大小写不敏感映射并注入 -c:v' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\src\a.png' -OutputPath 'D:\out\a.jpg' -OutputFormat 'JPG'
            }

            $result[5] | Should -Be 'mjpeg'
        }

        It '未知格式应回退为 libwebp 编码器' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\src\a.png' -OutputPath 'D:\out\a.bmp' -OutputFormat 'bmp'
            }

            $result[5] | Should -Be 'libwebp'
        }

        It '中文与含空格路径应原样保真' {
            $imagePath = 'D:\输出 目录\原始 图片.png'
            $outputPath = 'D:\输出 目录\结果 图片.webp'

            $result = InModuleScope IPAP -Parameters @{ Src = $imagePath; Dst = $outputPath } -ScriptBlock {
                param($Src, $Dst)
                Get-FfmpegArgument -ImagePath $Src -OutputPath $Dst -OutputFormat 'webp'
            }

            $result[1] | Should -Be $imagePath
            $result[9] | Should -Be $outputPath
        }
    }

    # L4：函数体无分支，唯一分支（编码器回退）在 Get-FfmpegCodec，已由其 L4 用例覆盖。

    Context 'L5 输出字段' {
        It '应返回 10 个元素且每个元素都是 string' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\a.png' -OutputPath 'D:\b.webp' -OutputFormat 'webp'
            }

            $result.Count | Should -Be 10
            foreach ($item in $result) {
                $item | Should -BeOfType [string]
            }
        }

        It '运行时数组类型应为 Object[]（函数输出经管道展开）' {
            $result = InModuleScope IPAP {
                Get-FfmpegArgument -ImagePath 'C:\a.png' -OutputPath 'D:\b.webp' -OutputFormat 'webp'
            }

            ($result -is [object[]]) | Should -BeTrue
            ($result -is [string[]]) | Should -BeFalse
        }
    }
}
