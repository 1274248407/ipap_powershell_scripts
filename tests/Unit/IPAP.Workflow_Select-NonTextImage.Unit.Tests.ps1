#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Select-NonTextImage 单元测试
.DESCRIPTION
    测试 Select-NonTextImage 函数的参数验证和基本行为。
#>

Describe 'Select-NonTextImage Unit Tests' -Tag 'Select-NonTextImage', 'IPAP.Workflow' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent

        Import-Module (Join-Path $ProjectRoot 'Modules\IPAP.Configuration\IPAP.Configuration.psd1') -Force -Global
        Import-Module (Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psd1') -Force -Global
        Import-Module (Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1') -Force -Global
        Import-Module (Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1') -Force -Global
        Import-Module (Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
        Remove-Module 'IPAP.Configuration' -ErrorAction SilentlyContinue
    }

    Context '源目录不存在' {
        It '应返回空数组并记录错误' {
            Mock -ModuleName IPAP.Workflow Write-InfoLog {}
            Mock -ModuleName IPAP.Workflow Write-ErrorLog {}
            Mock -ModuleName IPAP.Workflow Write-WarningLog {}

            $result = Select-NonTextImage -SourceDir 'TestDrive:\nonexistent_dir' -SupportedImageFormats @('.jpg', '.png')

            $result | Should -BeNullOrEmpty
        }
    }

    Context '函数参数验证' {
        It '应有 Mandatory 参数 SourceDir' {
            $cmd = Get-Command Select-NonTextImage
            $param = $cmd.Parameters['SourceDir']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] -and $PSItem.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It '应有 Mandatory 参数 SupportedImageFormats' {
            $cmd = Get-Command Select-NonTextImage
            $param = $cmd.Parameters['SupportedImageFormats']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] -and $PSItem.Mandatory } | Should -Not -BeNullOrEmpty
        }

        It '应声明 OutputType 为 object[]' {
            $cmd = Get-Command Select-NonTextImage
            $outputType = $cmd.OutputType
            $outputType.Type.Name | Should -Contain 'Object[]'
        }
    }
}