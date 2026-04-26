#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ProjectManager - New-ProjectStructure 单元测试
.DESCRIPTION
    测试 New-ProjectStructure 函数的目录创建逻辑。
#>

Describe 'New-ProjectStructure Unit Tests' -Tag 'New-ProjectStructure', 'IPAP.ProjectManager' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
        Mock -ModuleName IPAP.ProjectManager Write-ErrorLog {}
        Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
        Mock -ModuleName IPAP.ProjectManager New-Item {}
        Mock Read-Host {}
    }

    AfterAll {
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '新目录应成功创建' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject'

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match 'TestProject$'
        }

        It '应创建所有必需的子目录' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject'

            Assert-MockCalled -ModuleName IPAP.ProjectManager New-Item -Times 8
        }
    }

    Context '目录已存在处理 - Directory Exists' {
        It '目录已存在时应询问用户' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $true }
            Mock Read-Host { return 'Y' }
            Mock -ModuleName IPAP.ProjectManager New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'ExistingProject'

            Assert-MockCalled Read-Host -Times 1
        }

        It '用户选择覆盖时应创建目录' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $true }
            Mock Read-Host { return 'Y' }
            Mock -ModuleName IPAP.ProjectManager New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'ExistingProject'

            Assert-MockCalled -ModuleName IPAP.ProjectManager New-Item -Times 8
        }

        It '用户拒绝覆盖时应返回 $null' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $true }
            Mock Read-Host { return 'N' }

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'ExistingProject'

            $result | Should -BeNullOrEmpty
            Assert-MockCalled -ModuleName IPAP.ProjectManager New-Item -Times 0
        }

        It '用户输入小写 y 应视为同意' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $true }
            Mock Read-Host { return 'y' }
            Mock -ModuleName IPAP.ProjectManager New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'ExistingProject'

            Assert-MockCalled -ModuleName IPAP.ProjectManager New-Item -Times 8
        }
    }

    Context '必填参数测试 - Mandatory Parameters' {
        It 'BaseDir 缺失时应报错' {
            { New-ProjectStructure -ProjectName 'Test' } | Should -Throw
        }

        It 'ProjectName 缺失时应报错' {
            { New-ProjectStructure -BaseDir 'C:\Projects' } | Should -Throw
        }
    }

    Context '错误处理测试 - Error Handling' {
        It 'New-Item 失败时应返回 $null' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item { throw 'Access denied' }

            $result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject'

            $result | Should -BeNullOrEmpty
            Assert-MockCalled -ModuleName IPAP.ProjectManager Write-ErrorLog -Times 1
        }
    }

    Context '路径边界测试 - Path Boundary' {
        It '空字符串 BaseDir 应处理' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}

            $result = New-ProjectStructure -BaseDir '' -ProjectName 'Test'

            $result | Should -Not -BeNullOrEmpty
        }

        It '带空格的路径应处理' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}

            $result = New-ProjectStructure -BaseDir 'C:\Program Files\Projects' -ProjectName 'Test Project'

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
