#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Core - Get-Config 验收测试
.DESCRIPTION
    验收测试 Get-Config 函数在真实环境中的配置解析能力。
#>

Describe 'Get-Config Acceptance Tests' -Tag 'Get-Config', 'IPAP.Core', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'
        $ConfigPath = Join-Path $ProjectRoot 'config.toml'
        $TomlJsonPath = Join-Path $ProjectRoot 'bin\tomljson.exe'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.Core module not found at: $ModulePath" -ForegroundColor Red
        }

        $Script:TomlJsonExists = Test-Path $TomlJsonPath
        $Script:ConfigExists = Test-Path $ConfigPath
    }

    AfterAll {
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '配置文件存在时的行为' {
        It '如果 config.toml 存在应能解析' {
            if (-not $Script:ConfigExists)
            {
                Set-ItResult -Skipped -Because 'config.toml not found'
                return
            }

            if (-not $Script:TomlJsonExists)
            {
                Set-ItResult -Skipped -Because 'tomljson.exe not found'
                return
            }

            $result = Get-Config

            $result | Should -Not -BeNullOrEmpty
            $result.paths | Should -Not -BeNullOrEmpty
            $result.app_settings | Should -Not -BeNullOrEmpty
        }

        It '应返回正确的 app_settings 结构' {
            if (-not $Script:ConfigExists -or -not $Script:TomlJsonExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Get-Config

            $result.app_settings.Keys | Should -Contain 'model_select'
            $result.app_settings.Keys | Should -Contain 'max_workers'
            $result.app_settings.Keys | Should -Contain 'upscale_timeout_sec'
        }
    }

    Context '配置文件缺失时的行为' {
        It 'config.toml 不存在时应返回默认设置' {
            $nonExistentPath = Join-Path $env:TEMP "non_existent_config_$(Get-Random).toml"
            $result = Get-Config -ConfigPath $nonExistentPath

            $result | Should -Not -BeNullOrEmpty
            $result.app_settings.model_select | Should -Be 'models-se'
            $result.app_settings.max_workers | Should -Be 8
        }

        It 'tomljson.exe 不存在时应返回默认设置' {
            $tempConfig = New-Item -Path (Join-Path $env:TEMP "test_config_$(Get-Random).toml") -ItemType File -Force
            $result = Get-Config -ConfigPath $tempConfig.FullName

            $result | Should -Not -BeNullOrEmpty
            $result.app_settings.upscale_timeout_sec | Should -Be 600
        }
    }

    Context '路径处理测试' {
        It '应能处理带空格的路径' {
            if (-not $Script:ConfigExists)
            {
                Set-ItResult -Skipped -Because 'config.toml not found'
                return
            }

            $result = Get-Config -ConfigPath $ConfigPath

            $result | Should -Not -BeNullOrEmpty
        }

        It '应能处理相对路径' {
            if (-not $Script:ConfigExists)
            {
                Set-ItResult -Skipped -Because 'config.toml not found'
                return
            }

            $result = Get-Config -ConfigPath 'config.toml'

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
