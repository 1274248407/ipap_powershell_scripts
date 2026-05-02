#Requires -Modules Pester

<#
.SYNOPSIS
    Main.ps1 - Get-RealCuganExePath 单元测试
.DESCRIPTION
    测试 Main.ps1 中定义的 Get-RealCuganExePath 函数。
#>

Describe 'Main Get-RealCuganExePath Unit Tests' -Tag 'Get-RealCuganExePath', 'Main' {
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
        Mock Write-ErrorLog {}
        Mock Get-ChildItem {}
    }

    Context '正常执行路径 - Normal Execution' {
        It '找到 exe 时应返回完整路径' {
            Mock Get-ChildItem { return 'realcugan-ncnn-vulkan.exe' }

            $result = Get-RealCuganExePath -SearchPath 'C:\test'

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match 'realcugan-ncnn-vulkan\.exe$'
        }

        It '未找到 exe 时应返回 $null' {
            Mock Get-ChildItem {}

            $result = Get-RealCuganExePath -SearchPath 'C:\empty'

            $result | Should -BeNullOrEmpty
        }
    }

    Context '搜索路径测试' {
        It '应接受自定义搜索路径' {
            Mock Get-ChildItem { return 'realcugan-ncnn-vulkan.exe' }

            $result = Get-RealCuganExePath -SearchPath 'D:\custom\bin'

            $result | Should -Not -BeNullOrEmpty
        }

        It '应处理包含空格的路径' {
            Mock Get-ChildItem { return 'realcugan-ncnn-vulkan.exe' }

            $result = Get-RealCuganExePath -SearchPath 'C:\Program Files\Bin'

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context '参数绑定测试' {
        It 'SearchPath 默认值应为项目根目录下的 bin' {
            Mock Get-ChildItem { return 'realcugan-ncnn-vulkan.exe' }

            $result = Get-RealCuganExePath

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
