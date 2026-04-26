#Requires -Modules Pester

<#
.SYNOPSIS
    Main.ps1 - Get-Config 单元测试
.DESCRIPTION
    测试 Main.ps1 中定义的 Get-Config 函数。
#>

Describe 'Main Get-Config Unit Tests' -Tag 'Get-Config', 'Main' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
        $MainScriptPath = Join-Path $ProjectRoot 'Main.ps1'

        if (Test-Path $MainScriptPath)
        {
            . $MainScriptPath
        }

        Mock Write-InfoLog {}
        Mock Write-WarningLog {}
        Mock Write-ErrorLog {}
        Mock Test-Path { return $false }
    }

    Context '默认行为 - Default Behavior' {
        It '配置文件不存在时应返回默认设置' {
            $result = Get-Config

            $result | Should -Not -BeNullOrEmpty
            $result.app_settings.model_select | Should -Be 'models-se'
            $result.app_settings.max_workers | Should -Be 8
            $result.app_settings.upscale_timeout_sec | Should -Be 600
        }
    }

    Context '配置文件路径测试' {
        It '应接受自定义配置文件路径' {
            Mock Test-Path { return $false }

            $result = Get-Config -ConfigPath 'C:\custom\path\config.toml'

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'tomljson.exe 缺失测试' {
        It 'tomljson.exe 不存在时应返回默认设置' {
            Mock Test-Path -ParameterFilter { $Path -match 'tomljson' } { return $false }
            Mock Test-Path -ParameterFilter { $Path -notmatch 'tomljson' } { return $true }

            $result = Get-Config

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
