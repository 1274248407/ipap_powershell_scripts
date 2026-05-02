#Requires -Modules Pester

<#
.SYNOPSIS
    Main.ps1 - Get-Config 单元测试
.DESCRIPTION
    测试 Main.ps1 中定义的 Get-Config 函数。
#>

Describe 'Main Get-Config Unit Tests' -Tag 'Get-Config', 'Main' {
    BeforeAll {
        $ProjectRoot = $PSScriptRoot | Split-Path -Parent | Split-Path -Parent
        $MainScriptPath = Join-Path $ProjectRoot 'Main.ps1'
        
        # 导入 PoShLog 模块
        $PoshLogModulePath = Join-Path $ProjectRoot 'vendor\PoShLog\2.1.1\PoShLog.psd1'
        if (Test-Path $PoshLogModulePath)
        {
            Import-Module $PoshLogModulePath -Force
            New-Logger | Set-MinimumLevel -Value Verbose | Add-SinkConsole | Start-Logger
        }

        # 直接导入 Main.ps1（现在只加载函数，不执行主工作流）
        if (Test-Path $MainScriptPath)
        {
            . $MainScriptPath
        }

        # Mock 日志函数和依赖函数
        Mock Write-InfoLog {}
        Mock Write-WarningLog {}
        Mock Write-ErrorLog {}
        Mock Test-Path { return $false }
    }

    Context '默认行为 - Default Behavior' {
        It '配置文件不存在时应返回完整的默认设置' {
            $result = Get-Config

            # 验证结果不为空
            $result | Should -Not -BeNullOrEmpty
            
            # 验证 paths 部分的默认值
            $result.paths | Should -Not -BeNullOrEmpty
            $result.paths.base_project_dir | Should -Be ''
            $result.paths.project_dir_prefix | Should -Be ''
            
            # 验证 app_settings 部分的默认值
            $result.app_settings | Should -Not -BeNullOrEmpty
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

        It '应正确读取自定义配置文件的内容' {
            # 模拟配置文件存在
            Mock Test-Path -ParameterFilter { $Path -eq 'C:\custom\config.toml' } { return $true }
            Mock Test-Path -ParameterFilter { $Path -match 'tomljson' } { return $true }
            
            # 模拟 Invoke-TomlJsonExe 函数返回自定义配置的 JSON
            $customConfigJson = @{
                paths        = @{
                    base_project_dir   = 'C:\MyProjects'
                    project_dir_prefix = 'manga_'
                }
                app_settings = @{
                    model_select        = 'models-pro'
                    max_workers         = 16
                    upscale_timeout_sec = 1200
                }
            } | ConvertTo-Json
            
            Mock Invoke-TomlJsonExe { return $customConfigJson }

            # 调用函数
            $result = Get-Config -ConfigPath 'C:\custom\config.toml'

            # 验证返回的是自定义配置而不是默认配置
            $result | Should -Not -BeNullOrEmpty
            $result.paths.base_project_dir | Should -Be 'C:\MyProjects'
            $result.paths.project_dir_prefix | Should -Be 'manga_'
            $result.app_settings.model_select | Should -Be 'models-pro'
            $result.app_settings.max_workers | Should -Be 16
            $result.app_settings.upscale_timeout_sec | Should -Be 1200
        }
    }

    Context 'tomljson.exe 缺失测试' {
        It 'tomljson.exe 不存在时应返回完整的默认设置' {
            Mock Test-Path -ParameterFilter { $Path -match 'tomljson' } { return $false }
            Mock Test-Path -ParameterFilter { $Path -notmatch 'tomljson' } { return $true }

            $result = Get-Config

            # 验证结果不为空
            $result | Should -Not -BeNullOrEmpty
            
            # 验证 paths 部分的默认值
            $result.paths | Should -Not -BeNullOrEmpty
            $result.paths.base_project_dir | Should -Be ''
            $result.paths.project_dir_prefix | Should -Be ''
            
            # 验证 app_settings 部分的默认值
            $result.app_settings | Should -Not -BeNullOrEmpty
            $result.app_settings.model_select | Should -Be 'models-se'
            $result.app_settings.max_workers | Should -Be 8
            $result.app_settings.upscale_timeout_sec | Should -Be 600
        }
    }
}
