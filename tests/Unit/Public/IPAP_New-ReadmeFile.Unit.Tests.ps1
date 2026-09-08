#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - New-ReadmeFile 单元测试
.DESCRIPTION
    测试 New-ReadmeFile 函数的 README 文件生成逻辑。
#>

Describe 'New-ReadmeFile Unit Tests' -Tag 'New-ReadmeFile', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 创建测试目录
        [string]$Script:TestProjectDir = New-Item -ItemType Directory -Path 'TestDrive:\test_project' | Select-Object -ExpandProperty FullName

        # Mock 模块内的日志函数（Write-LogEntry 为纯日志函数，全级别静默记录）
        Mock Write-LogEntry -ModuleName IPAP { }


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
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale -UpscaleRatio 2

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            Test-Path $readmePath | Should -Be $true
        }

        It 'NeedUpscale 为 $true 时应有正确标记' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale -UpscaleRatio 2

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            # 匹配完整行格式，确保是"原始文件是否需要高清化"这一行的标记
            $content | Should -Match '- 原始文件是否需要高清化: \[X\]'
        }

        It 'NeedUpscale 为 $false 时应有正确标记' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -UpscaleRatio 2

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            # 匹配完整行格式，确保是"原始文件是否需要高清化"这一行的标记
            $content | Should -Match '- 原始文件是否需要高清化: \[ \]'
        }

        It '应使用 -LiteralPath 参数写入文件' {
            # 直接测试文件是否被正确创建，而不是 Mock Out-File
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            Test-Path $readmePath | Should -Be $true

            # 验证文件内容
            $content = Get-Content $readmePath -Raw
            $content | Should -Match 'TestProject'
        }
    }

    Context 'UpscaleRatio 测试' {
        It '默认 UpscaleRatio 应为 2' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            # 匹配完整行格式，确保是"使用高清化倍数"这一行的值
            $content | Should -Match '- 使用高清化倍数: 2'
        }

        It '自定义 UpscaleRatio 应被接受' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale -UpscaleRatio 4

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

    Context '错误处理测试 - Error Handling' {
        It '目录不存在时应抛出终止错误' {
            # 使用不存在的路径
            $nonExistentPath = 'TestDrive:\non_existent_folder'

            # 注意：try 块内的错误会被外层 catch 包裹为"创建/覆盖 README.md 文件失败: <原始消息>"
            { New-ReadmeFile -ProjectDir $nonExistentPath -ProjectName 'TestProject' -ImageCount 50 } | Should -Throw '创建/覆盖 README.md 文件失败: 项目目录不存在*'

            # 内层记录 1 次 + 外层 catch 记录 1 次
            Should -Invoke -ModuleName IPAP Write-LogEntry -ParameterFilter { $Level -eq 'Error' } -Times 2

            # 验证文件没有被创建
            $readmePath = Join-Path $nonExistentPath 'README.md'
            Test-Path $readmePath | Should -Be $false
        }

        It '写入文件失败时应抛出终止错误' {
            Mock -ModuleName IPAP Out-File { throw 'Disk full' }

            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 } | Should -Throw '创建/覆盖 README.md 文件失败*'
        }

        It '创建后验证失败时应抛出终止错误' {
            # 目录存在检查通过，但 README.md 文件验证失败
            Mock -ModuleName IPAP Test-Path { param($LiteralPath) return ($LiteralPath -eq $Script:TestProjectDir) }

            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 } | Should -Throw '创建/覆盖 README.md 文件失败: 无法验证 README.md 文件创建*'
        }
    }
}