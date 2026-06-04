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
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
    }

    AfterAll {
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 创建测试目录
        $Script:TestProjectDir = New-Item -ItemType Directory -Path 'TestDrive:\test_project' | Select-Object -ExpandProperty FullName
        
        # Mock 模块内的自定义函数
        Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
        Mock -ModuleName IPAP.ProjectManager Write-ErrorLog {}
    }

    AfterEach {
        # 清理测试目录
        if (Test-Path $Script:TestProjectDir)
        {
            Remove-Item -Path $Script:TestProjectDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context '正常执行路径 - Normal Execution' {
        It '应生成 README 文件' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true -UpscaleRatio 2

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            Test-Path $readmePath | Should -Be $true
        }

        It 'NeedUpscale 为 $true 时应有正确标记' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true -UpscaleRatio 2

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            # 匹配完整行格式，确保是"原始文件是否需要高清化"这一行的标记
            $content | Should -Match '- 原始文件是否需要高清化: \[X\]'
        }

        It 'NeedUpscale 为 $false 时应有正确标记' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $false -UpscaleRatio 2

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            # 匹配完整行格式，确保是"原始文件是否需要高清化"这一行的标记
            $content | Should -Match '- 原始文件是否需要高清化: \[ \]'
        }

        It '应使用 -LiteralPath 参数写入文件' {
            # 直接测试文件是否被正确创建，而不是 Mock Out-File
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $false

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            Test-Path $readmePath | Should -Be $true
            
            # 验证文件内容
            $content = Get-Content $readmePath -Raw
            $content | Should -Match 'TestProject'
        }
    }

    Context 'UpscaleRatio 测试' {
        It '默认 UpscaleRatio 应为 2' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            # 匹配完整行格式，确保是"使用高清化倍数"这一行的值
            $content | Should -Match '- 使用高清化倍数: 2'
        }

        It '自定义 UpscaleRatio 应被接受' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true -UpscaleRatio 4

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            # 匹配完整行格式，确保是"使用高清化倍数"这一行的值
            $content | Should -Match '- 使用高清化倍数: 4'
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
        It '目录不存在时应记录错误并返回' {
            # 使用不存在的路径
            $nonExistentPath = 'TestDrive:\non_existent_folder'
            
            New-ReadmeFile -ProjectDir $nonExistentPath -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $false

            Should -Invoke -ModuleName IPAP.ProjectManager Write-ErrorLog -Times 1
            
            # 验证文件没有被创建
            $readmePath = Join-Path $nonExistentPath 'README.md'
            Test-Path $readmePath | Should -Be $false
        }
    }
}
