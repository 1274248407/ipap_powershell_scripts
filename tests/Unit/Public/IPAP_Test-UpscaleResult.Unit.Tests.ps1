#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Test-UpscaleResult 单元测试
.DESCRIPTION
    测试 Test-UpscaleResult 函数的结果验证逻辑，包括边界条件和错误处理。
    注意：源码新增 Test-Path 守卫，且 Write-ErrorLog 具有真实 throw 语义，
    因此"输出目录不存在"和"完全失败"场景会抛出终止错误。
#>

Describe 'Test-UpscaleResult Unit Tests' -Tag 'Test-UpscaleResult', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 初始化配置实例（供 Test-SupportedImageFormat 内部读取）
        $MockPathsConfig = [PSCustomObject]@{
            ProjectRoot = 'C:\Projects'
            BinPath     = 'C:\Projects\bin'
            ConfigPath  = 'C:\Projects\config.toml'
        }
        $MockToolsConfig = [PSCustomObject]@{
            RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
            FfmpegExePath    = 'C:\bin\ffmpeg.exe'
            FfprobeExePath   = 'C:\bin\ffprobe.exe'
        }
        $MockAppConfig = [PSCustomObject]@{
            SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
            MaxWorkers            = 8
            UpscaleTimeoutSec     = 600
            ModelSelect           = 'models-se'
            UpscaleRatio          = 2
            NoiseLevel            = 0
        }
        $Global:IPAPConfigInstance = [PSCustomObject]@{
            Paths = $MockPathsConfig
            Tools = $MockToolsConfig
            App   = $MockAppConfig
        }

        # 使用全局 Mock（Write-ErrorLog 模拟真实 throw 语义）
        Mock -ModuleName IPAP Write-InfoLog {}
        Mock -ModuleName IPAP Write-WarningLog {}
        Mock -ModuleName IPAP Write-ErrorLog { param($Message) throw $Message }
        Mock -ModuleName IPAP Test-Path { return $true }
        Mock -ModuleName IPAP Get-ChildItem { return @() }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常处理结果 - Normal Processing Results' {
        It '所有图片处理成功时应返回 $true' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' },
                    [PSCustomObject]@{ Name = 'image2.jpg'; Extension = '.jpg' },
                    [PSCustomObject]@{ Name = 'image3.png'; Extension = '.png' }
                )
            }

            $result = Test-UpscaleResult -ExpectedCount 3 -OutputDir 'C:\output'

            $result | Should -Be $true
        }

        It '部分成功时应返回 $false' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' },
                    [PSCustomObject]@{ Name = 'image2.jpg'; Extension = '.jpg' }
                )
            }

            $result = Test-UpscaleResult -ExpectedCount 5 -OutputDir 'C:\output'

            $result | Should -Be $false
        }

        It '全部失败时应抛出终止错误' {
            Mock -ModuleName IPAP Get-ChildItem { return @() }

            { Test-UpscaleResult -ExpectedCount 3 -OutputDir 'C:\output' } | Should -Throw '并行处理完全失败*'
        }
    }

    Context '边界条件测试 - Boundary Conditions' {
        It 'ExpectedCount 为 0 且存在多余文件时应抛出除零错误' {
            # 源码在分支判断前先计算成功率，ExpectedCount=0 会触发 DivideByZeroException
            Mock -ModuleName IPAP Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                )
            }

            { Test-UpscaleResult -ExpectedCount 0 -OutputDir 'C:\output' } |
                Should -Throw -ExceptionType ([System.Management.Automation.RuntimeException])
        }

        It 'ExpectedCount 为负数且无输出时应抛出终止错误' {
            Mock -ModuleName IPAP Get-ChildItem { return @() }

            { Test-UpscaleResult -ExpectedCount -1 -OutputDir 'C:\output' } | Should -Throw '并行处理完全失败*'
        }

        It 'OutputDir 为空字符串时应处理' {
            Mock -ModuleName IPAP Get-ChildItem { throw 'Path cannot be empty' }

            { Test-UpscaleResult -ExpectedCount 3 -OutputDir '' } | Should -Throw
        }

        It 'OutputDir 为 $null 时应处理' {
            { Test-UpscaleResult -ExpectedCount 3 -OutputDir $null } | Should -Throw
        }
    }

    Context '文件类型过滤测试 - File Type Filtering' {
        It '应只统计支持的图片格式' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' },
                    [PSCustomObject]@{ Name = 'image2.txt'; Extension = '.txt' },
                    [PSCustomObject]@{ Name = 'image3.png'; Extension = '.png' },
                    [PSCustomObject]@{ Name = 'image4.pdf'; Extension = '.pdf' }
                )
            }

            $result = Test-UpscaleResult -ExpectedCount 2 -OutputDir 'C:\output'

            $result | Should -Be $true
        }
    }

    Context '目录不存在测试 - Directory Not Found' {
        It 'OutputDir 不存在时应抛出终止错误' {
            Mock -ModuleName IPAP Test-Path { return $false }

            { Test-UpscaleResult -ExpectedCount 3 -OutputDir 'C:\nonexistent' } | Should -Throw '输出目录不存在*'
        }
    }
}
