#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Start-IPAPWorkflow 单元测试
.DESCRIPTION
    测试 Start-IPAPWorkflow 函数的工作流执行逻辑。
#>

Describe 'Start-IPAPWorkflow Unit Tests' -Tag 'Start-IPAPWorkflow', 'IPAP.Workflow' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.Workflow Write-InfoLog {}
        Mock -ModuleName IPAP.Workflow Write-WarningLog {}
        Mock -ModuleName IPAP.Workflow Write-ErrorLog {}
        Mock -ModuleName IPAP.Workflow Initialize-Environment {}
        Mock -ModuleName IPAP.Workflow Get-ProjectBriefInfo { return 'Brief text', 'ProjectName' }
        Mock -ModuleName IPAP.Workflow New-ProjectStructure { return 'C:\Projects\2026-01-01_ProjectName' }
        Mock -ModuleName IPAP.Workflow Get-ImageInfo { return @{ Images = @(); Count = 0; AverageSize = 500; TotalSize = 0 } }
        Mock -ModuleName IPAP.Workflow Test-NeedUpscale { return $true }
        Mock -ModuleName IPAP.Workflow New-ReadmeFile {}
        Mock -ModuleName IPAP.Workflow New-TranslationFiles {}
        Mock -ModuleName IPAP.Workflow Invoke-ParallelUpscale { return @{ SuccessCount = 0; FailedCount = 0 } }
        Mock Read-Host {}
    }

    AfterAll {
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
    }

    Context '参数绑定测试' {
        It '应接受 BaseDir 参数' {
            Mock -ModuleName IPAP.Workflow Get-Config {
                return @{ paths = @{ base_project_dir = '' }; app_settings = @{} }
            }

            Start-IPAPWorkflow -BaseDir 'C:\Projects'

            Assert-MockCalled -ModuleName IPAP.Workflow Initialize-Environment -Times 1
        }

        It '应接受 ProjectName 参数' {
            Mock -ModuleName IPAP.Workflow Get-Config {
                return @{ paths = @{ base_project_dir = '' }; app_settings = @{} }
            }

            Start-IPAPWorkflow -ProjectName 'TestProject'

            Assert-MockCalled -ModuleName IPAP.Workflow Initialize-Environment -Times 1
        }

        It '应接受 SourceDir 参数' {
            Mock -ModuleName IPAP.Workflow Get-Config {
                return @{ paths = @{ base_project_dir = '' }; app_settings = @{} }
            }

            Start-IPAPWorkflow -SourceDir 'C:\Images'

            Assert-MockCalled -ModuleName IPAP.Workflow Initialize-Environment -Times 1
        }
    }

    Context '项目初始化测试' {
        It '应调用 Initialize-Environment' {
            Mock -ModuleName IPAP.Workflow Get-Config {
                return @{ paths = @{ base_project_dir = 'C:\' }; app_settings = @{ max_workers = 8 } }
            }

            Start-IPAPWorkflow

            Assert-MockCalled -ModuleName IPAP.Workflow Initialize-Environment -Times 1
        }

        It '应调用 Get-ProjectBriefInfo' {
            Mock -ModuleName IPAP.Workflow Get-Config {
                return @{ paths = @{ base_project_dir = 'C:\' }; app_settings = @{ max_workers = 8 } }
            }

            Start-IPAPWorkflow -BaseDir 'C:\Projects'

            Assert-MockCalled -ModuleName IPAP.Workflow Get-ProjectBriefInfo -Times 1
        }
    }

    Context '错误处理测试' {
        It 'New-ProjectStructure 返回 $null 时应处理' {
            Mock -ModuleName IPAP.Workflow Get-Config {
                return @{ paths = @{ base_project_dir = 'C:\' }; app_settings = @{ max_workers = 8 } }
            }
            Mock -ModuleName IPAP.Workflow New-ProjectStructure { return $null }

            Start-IPAPWorkflow -BaseDir 'C:\Projects'

            Assert-MockCalled -ModuleName IPAP.Workflow Write-ErrorLog -Times 1
        }
    }
}
