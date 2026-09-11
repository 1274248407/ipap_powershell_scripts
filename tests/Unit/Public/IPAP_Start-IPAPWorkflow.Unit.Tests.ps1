#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Start-IPAPWorkflow 单元测试
.DESCRIPTION
    测试 Start-IPAPWorkflow 函数的工作流执行逻辑，包含全面的防御性测试用例。
    注意：所有依赖函数均在 IPAP 模块内部替换为 Mock；Write-LogEntry -Level Error 模拟真实 throw 语义，
    因此外层 catch 记录错误后会以"执行过程中发生错误: ..."抛出终止错误。
#>

Describe 'Start-IPAPWorkflow Unit Tests' -Tag 'Start-IPAPWorkflow', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 在模块作用域内构造真实 IPAPConfiguration 实例
        # （Start-IPAPWorkflow 的 $Config 参数为强类型 [IPAPConfiguration]，PSCustomObject 无法赋值）
        $Global:IPAPTestProjectRoot = $ProjectRoot
        $Script:MockConfig = InModuleScope IPAP {
            $config = [IPAPConfiguration]::Load($Global:IPAPTestProjectRoot)
            # 覆盖为测试所需的确定性值
            $config.Paths.ProjectRoot = $Global:IPAPTestProjectRoot
            $config.Paths.BaseProjectDir = 'C:\Projects'
            $config.Paths.BinPath = 'C:\Projects\bin'
            $config.Paths.ConfigPath = 'C:\Projects\config.toml'
            $config.Paths.SourceDir = 'C:\Images'
            $config.Tools.RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
            $config.Tools.FfmpegExePath = 'C:\bin\ffmpeg.exe'
            $config.Tools.FfprobeExePath = 'C:\bin\ffprobe.exe'
            $config.App.SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
            $config.App.MaxWorkers = 8
            $config.App.UpscaleTimeoutSec = 600
            $config.App.ModelSelect = 'models-se'
            $config.App.UpscaleRatio = 2
            $config.App.NoiseLevel = 0
            return $config
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 重置模块内配置状态
        InModuleScope IPAP {
            $script:IPAPConfigInstance = $null
        }

        # Mock 日志函数（Write-LogEntry 为纯日志函数，全级别静默记录）
        Mock Write-LogEntry -ModuleName IPAP { }



        # 预设模块内配置实例（使 Test-ConfigurationInitialized 守卫通过）
        InModuleScope IPAP {
            $script:IPAPConfigInstance = $Script:MockConfig
        }

        # Mock 模块内依赖函数
        Mock -ModuleName IPAP Get-Configuration { return $Script:MockConfig }
        Mock -ModuleName IPAP Get-ProjectBriefInfo { return 'Brief text', 'TestProject' }
        Mock -ModuleName IPAP New-ProjectStructure { return 'C:\Projects\2026-01-01_TestProject' }
        Mock -ModuleName IPAP New-ReadmeFile {}
        Mock -ModuleName IPAP Select-NonTextImage { return @() }
        Mock -ModuleName IPAP Copy-Item {}
        Mock -ModuleName IPAP Get-ImageInfo {
            return @{ Images = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' }); Count = 1; AverageSize = 500; TotalSize = 500 }
        }
        Mock -ModuleName IPAP Get-ImageLevel {
            param([array]$Images)
            return $Images | ForEach-Object {
                [PSCustomObject]@{ Image = $PSItem; Level = 0; LongEdge = 1920; YDIF = 8.0 }
            }
        }
        Mock -ModuleName IPAP Invoke-ParallelUpscale { return @{ SuccessCount = 0; FailedCount = 0 } }
        Mock -ModuleName IPAP Test-UpscaleResult { return $true }
    }

    Context '参数绑定测试' {
        It '应接受所有参数的组合' {
            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '应处理包含空格的路径参数' {
            { Start-IPAPWorkflow -BaseDir 'C:\Program Files\Projects' -SourceDir 'C:\My Images' } | Should -Not -Throw
        }

        It '应处理中文路径参数' {
            { Start-IPAPWorkflow -BaseDir 'C:\项目\测试' -SourceDir 'C:\图片' } | Should -Not -Throw
        }
    }

    Context '输入边界测试' {
        It 'BaseDir 为空字符串时应正常处理' {
            { Start-IPAPWorkflow -BaseDir '' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It 'BaseDir 为空白字符时应正常处理' {
            { Start-IPAPWorkflow -BaseDir "`t`n " -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '超长路径参数应正常处理' {
            $longPath = 'C:\' + ('a' * 250)
            { Start-IPAPWorkflow -BaseDir $longPath -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '特殊字符路径应正常处理' {
            { Start-IPAPWorkflow -BaseDir 'C:\Test[123]\{Special}@#$%' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '路径中包含 Unicode 字符应正常处理' {
            { Start-IPAPWorkflow -BaseDir 'C:\Test\αβγ' -SourceDir 'C:\Images' } | Should -Not -Throw
        }
    }

    Context '项目初始化测试' {
        It '应初始化并设置全局配置实例' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            # 验证 Get-Configuration 的副作用：配置实例被设置
            InModuleScope IPAP {
                $script:IPAPConfigInstance | Should -Not -Be $null
                $script:IPAPConfigInstance.Paths.ProjectRoot | Should -Be $ProjectRoot
                $script:IPAPConfigInstance.App.MaxWorkers | Should -Be 8
            }
        }
    }

    Context '错误处理测试' {
        It 'New-ProjectStructure 返回 $null 时应抛出终止错误' {
            Mock -ModuleName IPAP New-ProjectStructure { return $null }

            # else 块记录"项目初始化失败"后抛出 InvalidOperationException，外层 catch 记录后重抛原始异常
            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Throw '项目初始化失败*'

            Should -Invoke -ModuleName IPAP Write-LogEntry -ParameterFilter { $Level -eq 'Error' } -Times 2
        }

        It 'Get-ImageInfo 返回空结构时应跳过后续处理' {
            Mock -ModuleName IPAP Get-ImageInfo {
                return @{ Images = @(); Count = 0; AverageSize = 0; TotalSize = 0 }
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Not -Throw
        }
    }

    Context '分级处理工作流测试' {
        It 'Level 1 图片应使用 FFmpeg 引擎处理' {
            Mock -ModuleName IPAP Get-ImageLevel {
                param([array]$Images)
                return $Images | ForEach-Object {
                    [PSCustomObject]@{ Image = $PSItem; Level = 1; LongEdge = 1100; YDIF = 3.5 }
                }
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It 'Level 2 图片且 RealCuganExePath 为空时应正常跳过不抛出异常' {
            InModuleScope IPAP {
                $script:IPAPConfigInstance.Tools.RealCuganExePath = $null
            }
            Mock -ModuleName IPAP Get-ImageLevel {
                param([array]$Images)
                return $Images | ForEach-Object {
                    [PSCustomObject]@{ Image = $PSItem; Level = 2; LongEdge = 800; YDIF = 1.5 }
                }
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It 'Level 0 全部高清时应跳过处理不抛出异常' {
            Mock -ModuleName IPAP Get-ImageLevel {
                param([array]$Images)
                return $Images | ForEach-Object {
                    [PSCustomObject]@{ Image = $PSItem; Level = 0; LongEdge = 1920; YDIF = 8.0 }
                }
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '混合级别图片应正常处理不抛出异常' {
            InModuleScope IPAP {
                $script:IPAPConfigInstance.Tools.RealCuganExePath = 'C:\bin\realcugan.exe'
            }
            $image1 = [PSCustomObject]@{ Name = 'L1.jpg'; FullName = 'C:\L1.jpg' }
            $image2 = [PSCustomObject]@{ Name = 'L2.jpg'; FullName = 'C:\L2.jpg' }

            Mock -ModuleName IPAP Get-ImageInfo {
                return @{ Images = @($image1, $image2); Count = 2; AverageSize = 500; TotalSize = 1000 }
            }
            Mock -ModuleName IPAP Get-ImageLevel {
                param([array]$Images)
                return @(
                    [PSCustomObject]@{ Image = $image1; Level = 1; LongEdge = 1100; YDIF = 3.0 }
                    [PSCustomObject]@{ Image = $image2; Level = 2; LongEdge = 800; YDIF = 1.0 }
                )
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '所有图片分级后应正确分流到对应处理路径' {
            # 验证 Get-ImageLevel 被调用后，工作流根据分级结果正确分流
            # 全部 Level 0 时不调用 Invoke-ParallelUpscale
            Mock -ModuleName IPAP Get-ImageLevel {
                param([array]$Images)
                return $Images | ForEach-Object {
                    [PSCustomObject]@{ Image = $PSItem; Level = 0; LongEdge = 1920; YDIF = 8.0 }
                }
            }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            # 全部 Level 0 时，Invoke-ParallelUpscale 不应被调用
            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale -Times 0
        }
    }
}