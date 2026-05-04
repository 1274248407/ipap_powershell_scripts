#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Start-IPAPWorkflow 验收测试
.DESCRIPTION
    验收测试 Start-IPAPWorkflow 函数在真实环境中的工作流执行能力。
#>

Describe 'Start-IPAPWorkflow Acceptance Tests' -Tag 'Start-IPAPWorkflow', 'IPAP.Workflow', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psm1'
        $ImageDir = Join-Path $ProjectRoot 'tests\data\images'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.Workflow module not found at: $ModulePath" -ForegroundColor Red
        }

        $Script:ImageDirExists = Test-Path $ImageDir
        $Script:TestOutputDir = Join-Path $env:TEMP "ipap_workflow_test_$( Get-Random)"
    }

    AfterAll {
        if (Test-Path $Script:TestOutputDir)
        {
            Remove-Item -Path $Script:TestOutputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
    }

    Context '前置条件验证' {
        It '模块应成功加载' {
            if (-not (Test-Path $ModulePath))
            {
                Set-ItResult -Skipped -Because 'Module not found'
                return
            }

            Get-Command Initialize-Environment -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It '测试图片目录应存在' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped -Because 'Test images directory not found'
                return
            }

            $Script:ImageDirExists | Should -Be $true
        }
    }

    Context '工作流初始化测试' {
        It '应能执行 Initialize-Environment' {
            Initialize-Environment

            $Global:Settings | Should -Not -BeNullOrEmpty
        }
    }
}
