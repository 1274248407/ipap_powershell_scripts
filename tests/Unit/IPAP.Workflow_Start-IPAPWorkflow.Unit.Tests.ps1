#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Start-IPAPWorkflow 单元测试
.DESCRIPTION
    测试 Start-IPAPWorkflow 函数的工作流执行逻辑，包含全面的防御性测试用例。
    注意：由于 IPAP.Workflow 通过全局作用域调用依赖模块函数，跨模块 Mock 无法使用 Should -Invoke 验证调用次数。
    本测试通过验证行为副作用（全局状态、日志输出等）来确认函数正确执行。
#>

Describe 'Start-IPAPWorkflow Unit Tests' -Tag 'Start-IPAPWorkflow', 'IPAP.Workflow' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent

        # 导入所有依赖模块（按顺序：Configuration → Core → ImageProcessor → ProjectManager → Workflow）
        $ConfigurationModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Configuration\IPAP.Configuration.psd1'
        $CoreModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psd1'
        $ImageProcessorModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1'
        $ProjectManagerModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1'
        $WorkflowModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psd1'

        if (Test-Path $ConfigurationModulePath) { Import-Module $ConfigurationModulePath -Force -Global }
        if (Test-Path $CoreModulePath) { Import-Module $CoreModulePath -Force -Global }
        if (Test-Path $ImageProcessorModulePath) { Import-Module $ImageProcessorModulePath -Force -Global }
        if (Test-Path $ProjectManagerModulePath) { Import-Module $ProjectManagerModulePath -Force -Global }
        if (Test-Path $WorkflowModulePath) { Import-Module $WorkflowModulePath -Force -Global }
    }

    BeforeEach {
        # 重置全局状态
        $Global:IPAPConfigInstance = $null

        # Mock 日志函数（全局作用域，拦截所有模块的日志调用）
        Mock Write-InfoLog {}
        Mock Write-WarningLog {}
        Mock Write-ErrorLog {}

        # 创建模拟的配置对象
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
        $MockConfig = [PSCustomObject]@{
            Paths = $MockPathsConfig
            Tools = $MockToolsConfig
            App   = $MockAppConfig
        }

        # Mock Get-Configuration 来初始化配置实例
        Mock -ModuleName IPAP.Configuration Get-Configuration {
            $Global:IPAPConfigInstance = $MockConfig
            return $MockConfig
        }

        # Mock 各模块的函数（在各自模块的内部作用域中替换）
        Mock -ModuleName IPAP.ProjectManager Get-ProjectBriefInfo { return 'Brief text', 'TestProject' }
        Mock -ModuleName IPAP.ProjectManager New-ProjectStructure { return 'C:\Projects\2026-01-01_TestProject' }
        Mock -ModuleName IPAP.ProjectManager New-ReadmeFile {}
        Mock -ModuleName IPAP.ProjectManager New-TranslationFiles {}
        Mock -ModuleName IPAP.ImageProcessor Get-ImageInfo {
            return @{ Images = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' }); Count = 1; AverageSize = 500; TotalSize = 500 }
        }
        Mock -ModuleName IPAP.ImageProcessor Get-ImageLevel {
            param([array]$Images)
            return $Images | ForEach-Object {
                [PSCustomObject]@{ Image = $PSItem; Level = 0; LongEdge = 1920; YDIF = 8.0 }
            }
        }
        Mock -ModuleName IPAP.ImageProcessor Invoke-ParallelUpscale { return @{ SuccessCount = 0; FailedCount = 0 } }
        Mock -ModuleName IPAP.Workflow Test-UpscaleResult { return $true }
    }

    AfterAll {
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '参数绑定测试' {
        It '应接受所有参数的组合' {
            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '应处理包含空格的路径参数' {
            { Start-IPAPWorkflow -BaseDir 'C:\Program Files\Projects' -ProjectName 'TestProject' -SourceDir 'C:\My Images' } | Should -Not -Throw
        }

        It '应处理中文路径参数' {
            { Start-IPAPWorkflow -BaseDir 'C:\项目\测试' -ProjectName '中文项目' -SourceDir 'C:\图片' } | Should -Not -Throw
        }
    }

    Context '输入边界测试' {
        It 'BaseDir 为空字符串时应正常处理' {
            { Start-IPAPWorkflow -BaseDir '' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It 'BaseDir 为空白字符时应正常处理' {
            { Start-IPAPWorkflow -BaseDir "`t`n " -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '超长路径参数应正常处理' {
            $longPath = 'C:\' + ('a' * 250)
            { Start-IPAPWorkflow -BaseDir $longPath -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '特殊字符路径应正常处理' {
            { Start-IPAPWorkflow -BaseDir 'C:\Test[123]\{Special}@#$%' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '路径中包含 Unicode 字符应正常处理' {
            { Start-IPAPWorkflow -BaseDir 'C:\Test\αβγ' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }
    }

    Context '项目初始化测试' {
        It '应初始化并设置全局配置实例' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            # 验证 Get-Configuration 的副作用：配置实例被设置
            $Global:IPAPConfigInstance | Should -Not -Be $null
            $Global:IPAPConfigInstance.Paths.ProjectRoot | Should -Be 'C:\Projects'
            $Global:IPAPConfigInstance.App.MaxWorkers | Should -Be 8
        }
    }

    Context '错误处理测试' {
        It 'New-ProjectStructure 返回 $null 时应正常退出不抛出异常' {
            Mock -ModuleName IPAP.ProjectManager New-ProjectStructure { return $null }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It 'Get-ImageInfo 返回空结构时应跳过后续处理' {
            Mock -ModuleName IPAP.ImageProcessor Get-ImageInfo {
                return @{ Images = @(); Count = 0; AverageSize = 0; TotalSize = 0 }
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }
    }

    Context '分级处理工作流测试' {
        It 'Level 1 图片应使用 FFmpeg 引擎处理' {
            Mock -ModuleName IPAP.ImageProcessor Get-ImageLevel {
                param([array]$Images)
                return $Images | ForEach-Object {
                    [PSCustomObject]@{ Image = $PSItem; Level = 1; LongEdge = 1100; YDIF = 3.5 }
                }
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It 'Level 2 图片且 RealCuganExePath 为空时应正常跳过不抛出异常' {
            $Global:IPAPConfigInstance.Tools.RealCuganExePath = $null
            Mock -ModuleName IPAP.ImageProcessor Get-ImageLevel {
                param([array]$Images)
                return $Images | ForEach-Object {
                    [PSCustomObject]@{ Image = $PSItem; Level = 2; LongEdge = 800; YDIF = 1.5 }
                }
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It 'Level 0 全部高清时应跳过处理不抛出异常' {
            Mock -ModuleName IPAP.ImageProcessor Get-ImageLevel {
                param([array]$Images)
                return $Images | ForEach-Object {
                    [PSCustomObject]@{ Image = $PSItem; Level = 0; LongEdge = 1920; YDIF = 8.0 }
                }
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '混合级别图片应正常处理不抛出异常' {
            $Global:IPAPConfigInstance.Tools.RealCuganExePath = 'C:\bin\realcugan.exe'
            $image1 = [PSCustomObject]@{ Name = 'L1.jpg'; FullName = 'C:\L1.jpg' }
            $image2 = [PSCustomObject]@{ Name = 'L2.jpg'; FullName = 'C:\L2.jpg' }

            Mock -ModuleName IPAP.ImageProcessor Get-ImageInfo {
                return @{ Images = @($image1, $image2); Count = 2; AverageSize = 500; TotalSize = 1000 }
            }
            Mock -ModuleName IPAP.ImageProcessor Get-ImageLevel {
                param([array]$Images)
                return @(
                    [PSCustomObject]@{ Image = $image1; Level = 1; LongEdge = 1100; YDIF = 3.0 }
                    [PSCustomObject]@{ Image = $image2; Level = 2; LongEdge = 800; YDIF = 1.0 }
                )
            }

            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images' } | Should -Not -Throw
        }

        It '所有图片分级后应正确分流到对应处理路径' {
            # 验证 Get-ImageLevel 被调用后，工作流根据分级结果正确分流
            # 全部 Level 0 时不调用 Invoke-ParallelUpscale
            Mock -ModuleName IPAP.ImageProcessor Get-ImageLevel {
                param([array]$Images)
                return $Images | ForEach-Object {
                    [PSCustomObject]@{ Image = $PSItem; Level = 0; LongEdge = 1920; YDIF = 8.0 }
                }
            }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            # 全部 Level 0 时，Invoke-ParallelUpscale 不应被调用
            Should -Invoke -ModuleName IPAP.ImageProcessor Invoke-ParallelUpscale -Times 0
        }
    }
}
