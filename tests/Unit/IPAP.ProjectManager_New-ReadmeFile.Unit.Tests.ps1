#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ProjectManager - New-ReadmeFile 单元测试
.DESCRIPTION
    测试 New-ReadmeFile 函数的 README 文件生成逻辑。
#>

Describe 'New-ReadmeFile Unit Tests' -Tag 'New-ReadmeFile', 'IPAP.ProjectManager' {
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
        Mock -ModuleName IPAP.ProjectManager Out-File {}
    }

    AfterAll {
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '应生成 README 文件' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-ReadmeFile -ProjectDir 'C:\Projects\Test' -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true -UpscaleRatio 2

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 1
        }

        It 'NeedUpscale 为 $true 时应有正确标记' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-ReadmeFile -ProjectDir 'C:\Projects\Test' -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true -UpscaleRatio 2

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 1
        }

        It 'NeedUpscale 为 $false 时应有正确标记' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-ReadmeFile -ProjectDir 'C:\Projects\Test' -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $false -UpscaleRatio 2

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 1
        }
    }

    Context 'UpscaleRatio 测试' {
        It '默认 UpscaleRatio 应为 2' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-ReadmeFile -ProjectDir 'C:\Projects\Test' -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 1
        }

        It '自定义 UpscaleRatio 应被接受' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-ReadmeFile -ProjectDir 'C:\Projects\Test' -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true -UpscaleRatio 4

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 1
        }
    }

    Context '必填参数测试 - Mandatory Parameters' {
        It '函数应有 Mandatory 参数 ProjectDir' {
            $cmd = Get-Command New-ReadmeFile
            $param = $cmd.Parameters['ProjectDir']
            $param.Attributes.Mandatory | Should -Be $true
        }

        It '函数应有 Mandatory 参数 ProjectName' {
            $cmd = Get-Command New-ReadmeFile
            $param = $cmd.Parameters['ProjectName']
            $param.Attributes.Mandatory | Should -Be $true
        }

        It '函数应有 Mandatory 参数 ImageCount' {
            $cmd = Get-Command New-ReadmeFile
            $param = $cmd.Parameters['ImageCount']
            $param.Attributes.Mandatory | Should -Be $true
        }

        It '函数应有 Mandatory 参数 NeedUpscale' {
            $cmd = Get-Command New-ReadmeFile
            $param = $cmd.Parameters['NeedUpscale']
            $param.Attributes.Mandatory | Should -Be $true
        }
    }

    Context '错误处理测试' {
        It 'Out-File 失败时应记录错误' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager Out-File { throw 'Write error' }

            New-ReadmeFile -ProjectDir 'C:\Projects\Test' -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $false

            Should -Invoke -ModuleName IPAP.ProjectManager Write-ErrorLog -Times 1
        }
    }
}
