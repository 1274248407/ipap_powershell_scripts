#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Initialize-ImageProcessor 验收测试
.DESCRIPTION
    验收测试 Initialize-ImageProcessor 函数在真实环境中的初始化能力。
#>

Describe 'Initialize-ImageProcessor Acceptance Tests' -Tag 'Initialize-ImageProcessor', 'IPAP.ImageProcessor', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'
        $BinPath = Join-Path $ProjectRoot 'bin'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.ImageProcessor module not found at: $ModulePath" -ForegroundColor Red
        }

        $Script:ExeExists = Test-Path (Join-Path $BinPath 'realcugan-ncnn-vulkan.exe')
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '正常初始化' {
        It '应成功初始化' {
            Initialize-ImageProcessor

            $Global:RealCuganExePath | Should -Not -BeNullOrEmpty
        }

        It 'exe 存在时应设置有效路径' {
            if (-not $Script:ExeExists)
            {
                Set-ItResult -Skipped -Because 'realcugan-ncnn-vulkan.exe not found'
                return
            }

            Initialize-ImageProcessor

            $Global:RealCuganExePath | Should -Match 'realcugan.*\.exe$'
            Test-Path $Global:RealCuganExePath | Should -Be $true
        }
    }

    Context '全局变量验证' {
        It 'RealCuganExePath 应为全局变量' {
            Initialize-ImageProcessor

            Get-Variable -Name RealCuganExePath -Scope Global | Should -Not -BeNullOrEmpty
        }
    }

    Context '重复初始化测试' {
        It '应允许重复初始化' {
            Initialize-ImageProcessor
            { Initialize-ImageProcessor } | Should -Not -Throw
        }
    }
}
