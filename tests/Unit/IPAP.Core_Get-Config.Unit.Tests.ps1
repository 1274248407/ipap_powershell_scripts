#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Core - Get-Config 单元测试
.DESCRIPTION
    测试 Get-Config 函数的配置解析、错误处理和默认值逻辑。
#>

Describe 'Get-Config Unit Tests' -Tag 'Get-Config', 'IPAP.Core' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.Core Write-InfoLog {}
        Mock -ModuleName IPAP.Core Write-WarningLog {}
        Mock -ModuleName IPAP.Core Write-ErrorLog {}
        Mock -ModuleName IPAP.Core Test-Path { return $false }
    }

    AfterAll {
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '默认行为 - Default Behavior' {
        It '配置文件不存在时应返回默认设置' {
            Mock -ModuleName IPAP.Core Test-Path { return $false } -ParameterFilter { $Path -notmatch 'tomljson' }
            Mock -ModuleName IPAP.Core Test-Path -ParameterFilter { $Path -match 'tomljson' } { return $false }

            $result = Get-Config

            $result | Should -Not -BeNullOrEmpty
            $result.paths | Should -Not -BeNullOrEmpty
            $result.app_settings | Should -Not -BeNullOrEmpty
            $result.app_settings.model_select | Should -Be 'models-se'
            $result.app_settings.max_workers | Should -Be 8
            $result.app_settings.upscale_timeout_sec | Should -Be 600
        }

        It '应返回包含正确结构的配置对象' {
            Mock -ModuleName IPAP.Core Test-Path { return $false }

            $result = Get-Config

            $result | Should -BeOfType [System.Hashtable]
            $result.Keys | Should -Contain 'paths'
            $result.Keys | Should -Contain 'app_settings'
        }
    }

    Context '配置文件路径测试 - Config Path Tests' {
        It '应接受自定义配置文件路径' {
            Mock -ModuleName IPAP.Core Test-Path { return $false }

            $customPath = 'C:\custom\path\config.toml'
            $result = Get-Config -ConfigPath $customPath

            $result | Should -Not -BeNullOrEmpty
        }

        It '应处理路径中的特殊字符' {
            Mock -ModuleName IPAP.Core Test-Path { return $false }

            $pathWithSpaces = 'C:\Program Files\My App\config.toml'
            $result = Get-Config -ConfigPath $pathWithSpaces

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context 'tomljson.exe 缺失测试 - TomlJson Missing Tests' {
        It 'tomljson.exe 不存在时应返回默认设置' {
            Mock -ModuleName IPAP.Core Test-Path -ParameterFilter { $Path -notmatch 'tomljson' } { return $true }
            Mock -ModuleName IPAP.Core Test-Path -ParameterFilter { $Path -match 'tomljson' } { return $false }

            $result = Get-Config

            $result | Should -Not -BeNullOrEmpty
            $result.app_settings.max_workers | Should -Be 8
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        It '应接受位置参数' {
            Mock -ModuleName IPAP.Core Test-Path { return $false }

            $result = Get-Config 'C:\test\config.toml'

            $result | Should -Not -BeNullOrEmpty
        }

        It 'ConfigPath 参数为空字符串时应处理' {
            Mock -ModuleName IPAP.Core Test-Path { return $false }

            $result = Get-Config -ConfigPath ''

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
