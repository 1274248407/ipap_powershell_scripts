#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Core - Get-RealCuganExePath 单元测试
.DESCRIPTION
    测试 Get-RealCuganExePath 函数的搜索逻辑和返回值验证。
#>

Describe 'Get-RealCuganExePath Unit Tests' -Tag 'Get-RealCuganExePath', 'IPAP.Core' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.Core Write-InfoLog {}
        Mock -ModuleName IPAP.Core Write-ErrorLog {}
        Mock -ModuleName IPAP.Core Get-ChildItem {}
    }

    AfterAll {
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '找到 exe 时应返回完整路径' {
            Mock -ModuleName IPAP.Core Get-ChildItem {
                return 'realcugan-ncnn-vulkan.exe'
            }

            $result = Get-RealCuganExePath -SearchPath 'C:\test'

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match 'realcugan-ncnn-vulkan\.exe$'
        }

        It '未找到 exe 时应返回 $null' {
            Mock -ModuleName IPAP.Core Get-ChildItem {}

            $result = Get-RealCuganExePath -SearchPath 'C:\empty'

            $result | Should -BeNullOrEmpty
        }
    }

    Context '搜索路径测试 - Search Path Tests' {
        It '应接受自定义搜索路径' {
            Mock -ModuleName IPAP.Core Get-ChildItem {
                return 'realcugan-ncnn-vulkan.exe'
            }

            $result = Get-RealCuganExePath -SearchPath 'D:\custom\bin'

            $result | Should -Not -BeNullOrEmpty
        }

        It '应处理包含空格的路径' {
            Mock -ModuleName IPAP.Core Get-ChildItem {
                return 'realcugan-ncnn-vulkan.exe'
            }

            $result = Get-RealCuganExePath -SearchPath 'C:\Program Files\Bin'

            $result | Should -Not -BeNullOrEmpty
        }

        It '应处理根目录路径' {
            Mock -ModuleName IPAP.Core Get-ChildItem {
                return 'realcugan-ncnn-vulkan.exe'
            }

            $result = Get-RealCuganExePath -SearchPath 'C:\'

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context '错误处理测试 - Error Handling' {
        It '搜索路径不存在时应处理' {
            Mock -ModuleName IPAP.Core Get-ChildItem {}

            $result = Get-RealCuganExePath -SearchPath 'C:\NonExistent'

            $result | Should -BeNullOrEmpty
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        It '应接受位置参数' {
            Mock -ModuleName IPAP.Core Get-ChildItem {
                return 'realcugan-ncnn-vulkan.exe'
            }

            $result = Get-RealCuganExePath 'C:\bin'

            $result | Should -Not -BeNullOrEmpty
        }

        It 'SearchPath 为空字符串时应处理' {
            Mock -ModuleName IPAP.Core Get-ChildItem {}

            $result = Get-RealCuganExePath -SearchPath ''

            $result | Should -BeNullOrEmpty
        }
    }
}
