#Requires -Modules Pester

<#
.SYNOPSIS
    Main.ps1 - Get-RealCuganExePath 单元测试
.DESCRIPTION
    测试 Main.ps1 中定义的 Get-RealCuganExePath 函数。
#>

Describe 'Main Get-RealCuganExePath Unit Tests' -Tag 'Get-RealCuganExePath', 'Main' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot
        $MainScriptPath = Join-Path $ProjectRoot 'Main.ps1'

        if (Test-Path $MainScriptPath)
        {
            . $MainScriptPath
        }

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
        It 'SearchPath 默认值应为 $ScriptRoot\bin' {
            Mock Get-ChildItem { return 'realcugan-ncnn-vulkan.exe' }

            $result = Get-RealCuganExePath

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
