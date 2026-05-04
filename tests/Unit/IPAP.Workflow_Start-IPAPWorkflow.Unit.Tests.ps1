#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Start-IPAPWorkflow 单元测试
.DESCRIPTION
    测试 Start-IPAPWorkflow 函数的工作流执行逻辑，包含全面的防御性测试用例。
#>

Describe 'Start-IPAPWorkflow Unit Tests' -Tag 'Start-IPAPWorkflow', 'IPAP.Workflow' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
    }

    BeforeEach {
        # 重置全局状态
        $Global:RealCuganExePath = $null
        $Global:Settings = $null

        # Mock 所有外部依赖
        Mock -ModuleName IPAP.Workflow Write-InfoLog {}
        Mock -ModuleName IPAP.Workflow Write-WarningLog {}
        Mock -ModuleName IPAP.Workflow Write-ErrorLog {}
        Mock -ModuleName IPAP.Workflow Initialize-Environment {
            $Global:Settings = @{ paths = @{ base_project_dir = 'C:\Projects' }; app_settings = @{} }
        }
        Mock -ModuleName IPAP.Workflow Get-ProjectBriefInfo { return 'Brief text', 'ProjectName' }
        Mock -ModuleName IPAP.Workflow New-ProjectStructure { return 'C:\Projects\2026-01-01_ProjectName' }
        Mock -ModuleName IPAP.Workflow Get-ImageInfo { return @{ Images = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' }); Count = 1; AverageSize = 500; TotalSize = 500 } }
        Mock -ModuleName IPAP.Workflow Test-NeedUpscale { return $false }
        Mock -ModuleName IPAP.Workflow New-ReadmeFile {}
        Mock -ModuleName IPAP.Workflow New-TranslationFiles {}
        Mock -ModuleName IPAP.Workflow Invoke-ParallelUpscale { return @{ SuccessCount = 0; FailedCount = 0 } }
        Mock -ModuleName IPAP.Workflow Get-Config {
            return @{ paths = @{ base_project_dir = 'C:\Projects'; project_dir_prefix = '' }; app_settings = @{ max_workers = 8; upscale_timeout_sec = 600; model_select = 'models-se' } }
        }
    }

    AfterAll {
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
    }

    Context '参数绑定测试' {
        It '应接受所有参数的组合' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP.Workflow Initialize-Environment -Times 1
        }

        It '应处理包含空格的路径参数' {
            Start-IPAPWorkflow -BaseDir 'C:\Program Files\Projects' -ProjectName 'TestProject' -SourceDir 'C:\My Images'

            Should -Invoke -ModuleName IPAP.Workflow Initialize-Environment -Times 1
        }

        It '应处理中文路径参数' {
            Start-IPAPWorkflow -BaseDir 'C:\项目\测试' -ProjectName '中文项目' -SourceDir 'C:\图片'

            Should -Invoke -ModuleName IPAP.Workflow Initialize-Environment -Times 1
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
        It '应调用 Initialize-Environment 并设置全局状态' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP.Workflow Initialize-Environment -Times 1
            $Global:Settings | Should -Not -Be $null
        }

        It '应按正确顺序调用依赖函数' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP.Workflow Initialize-Environment -Times 1 -Scope It
            Should -Invoke -ModuleName IPAP.Workflow Get-ProjectBriefInfo -Times 1 -Scope It
            Should -Invoke -ModuleName IPAP.Workflow New-ProjectStructure -Times 1 -Scope It
            Should -Invoke -ModuleName IPAP.Workflow Get-ImageInfo -Times 1 -Scope It
        }
    }

    Context '错误处理测试' {
        It 'New-ProjectStructure 返回 $null 时应记录错误并退出' {
            Mock -ModuleName IPAP.Workflow New-ProjectStructure { return $null }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP.Workflow Write-ErrorLog -Times 1
            Should -Invoke -ModuleName IPAP.Workflow Get-ImageInfo -Times 1
            Should -Not -Invoke -ModuleName IPAP.Workflow New-ReadmeFile
        }

        It 'Get-ImageInfo 返回空结构时应跳过后续处理' {
            Mock -ModuleName IPAP.Workflow Get-ImageInfo { return @{ Images = @(); Count = 0; AverageSize = 0; TotalSize = 0 } }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            Should -Not -Invoke -ModuleName IPAP.Workflow New-ReadmeFile
        }
    }

    Context '工作流分支测试' {
        It '需要高清化时应调用 Invoke-ParallelUpscale' {
            $Global:RealCuganExePath = 'C:\bin\realcugan.exe'
            Mock -ModuleName IPAP.Workflow Test-NeedUpscale { return $true }
            Mock -ModuleName IPAP.Workflow Get-ImageInfo { 
                return @{ Images = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' }); Count = 1; AverageSize = 500; TotalSize = 500 } 
            }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP.Workflow Invoke-ParallelUpscale -Times 1
        }

        It 'RealCuganExePath 为空时应跳过高清化' {
            $Global:RealCuganExePath = $null
            Mock -ModuleName IPAP.Workflow Test-NeedUpscale { return $true }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            Should -Not -Invoke -ModuleName IPAP.Workflow Invoke-ParallelUpscale
        }

        It '不需要高清化时应跳过高清化' {
            $Global:RealCuganExePath = 'C:\bin\realcugan.exe'
            Mock -ModuleName IPAP.Workflow Test-NeedUpscale { return $false }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -ProjectName 'TestProject' -SourceDir 'C:\Images'

            Should -Not -Invoke -ModuleName IPAP.Workflow Invoke-ParallelUpscale
        }
    }
}
