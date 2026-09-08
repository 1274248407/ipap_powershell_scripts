#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - New-ProjectStructure 单元测试
.DESCRIPTION
    测试 New-ProjectStructure 函数的目录创建逻辑。
    注意：源码使用 $PSCmdlet.ShouldContinue 进行覆盖确认，非交互环境下会抛出异常，
    因此覆盖场景统一使用 -Force 参数跳过确认进行测试。
#>

Describe 'New-ProjectStructure Unit Tests' -Tag 'New-ProjectStructure', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 使用全局 Mock（Write-ErrorLog 模拟真实 throw 语义）
        Mock -ModuleName IPAP Write-InfoLog {}
        Mock -ModuleName IPAP Write-WarningLog {}
        Mock -ModuleName IPAP Write-ErrorLog { param($Message) throw $Message }
        Mock -ModuleName IPAP Test-Path { return $false }
        Mock -ModuleName IPAP New-Item {}
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '新目录应成功创建' {
            Mock -ModuleName IPAP Test-Path { return $false }
            Mock -ModuleName IPAP New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject'

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match '\d{4}-\d{2}-\d{2}_TestProject$'
        }

        It '应创建所有必需的子目录' {
            Mock -ModuleName IPAP Test-Path { return $false }
            Mock -ModuleName IPAP New-Item {}

            New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject'

            # 1 个项目主目录 + 6 个子目录
            Should -Invoke -ModuleName IPAP New-Item -Times 7
        }
    }

    Context '目录已存在处理 - Directory Exists' {
        It '目录已存在且指定 -Force 时应跳过确认直接覆盖创建' {
            Mock -ModuleName IPAP Test-Path { return $true }
            Mock -ModuleName IPAP New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'ExistingProject' -Force

            Should -Invoke -ModuleName IPAP New-Item -Times 7
            $result | Should -Not -BeNullOrEmpty
        }

        It '目录已存在且指定 -Force 时应返回项目目录路径' {
            Mock -ModuleName IPAP Test-Path { return $true }
            Mock -ModuleName IPAP New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'ExistingProject' -Force

            $result | Should -Match '\d{4}-\d{2}-\d{2}_ExistingProject$'
        }
    }

    Context '必填参数测试 - Mandatory Parameters' {
        It '函数应有 Mandatory 参数 BaseDir' {
            $cmd = Get-Command New-ProjectStructure
            $param = $cmd.Parameters['BaseDir']
            $param.Attributes.Mandatory | Should -Be $true
        }

        It '函数应有 Mandatory 参数 ProjectName' {
            $cmd = Get-Command New-ProjectStructure
            $param = $cmd.Parameters['ProjectName']
            $param.Attributes.Mandatory | Should -Be $true
        }
    }

    Context '错误处理测试 - Error Handling' {
        It 'New-Item 失败时应抛出终止错误' {
            Mock -ModuleName IPAP Test-Path { return $false }
            Mock -ModuleName IPAP New-Item { throw 'Access denied' }

            { New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' } | Should -Throw '创建项目目录失败*'

            Should -Invoke -ModuleName IPAP Write-ErrorLog -Times 1
        }
    }

    Context '路径边界测试 - Path Boundary' {
        It '带空格的路径应处理' {
            Mock -ModuleName IPAP Test-Path { return $false }
            Mock -ModuleName IPAP New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Program Files\Projects' -ProjectName 'Test Project'

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match '\d{4}-\d{2}-\d{2}_Test Project$'
        }
    }
}
