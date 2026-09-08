#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Select-NonTextImage 单元测试
.DESCRIPTION
    测试 Select-NonTextImage 函数的参数验证和基本行为。
#>

Describe 'Select-NonTextImage Unit Tests' -Tag 'Select-NonTextImage', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '源目录不存在' {
        It '应抛出终止错误' {
            Mock Write-LogEntry -ModuleName IPAP { }



            { Select-NonTextImage -SourceDir 'TestDrive:\nonexistent_dir' -SupportedImageFormats @('.jpg', '.png') } | Should -Throw '源目录不存在*'
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

        It '应声明 OutputType 为 FileInfo' {
            $cmd = Get-Command Select-NonTextImage
            $outputType = $cmd.OutputType
            $outputType.Type.Name | Should -Contain 'FileInfo'
        }
    }
}