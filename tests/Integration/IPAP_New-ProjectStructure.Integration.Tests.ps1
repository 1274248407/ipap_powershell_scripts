#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - New-ProjectStructure 集成测试
.DESCRIPTION
    使用 Pester TestDrive 提供的真实文件系统，验证 New-ProjectStructure 与
    文件系统的协作行为：完整目录树创建、重复调用幂等性、失败守卫路径。
    统一使用 TestDrive 的物理根路径（Pester 管理的隔离临时目录）进行文件操作，
    规避内容写入 cmdlet 对 PSDrive 前缀路径的解析兼容性问题。
    不涉及任何外部工具（FFmpeg/FFprobe/Real-CUGAN）的真实执行。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'New-ProjectStructure 集成测试（真实文件系统协作）' -Tag 'Integration' {
    BeforeAll {
        # tests\Integration → 项目根（向上两级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # TestDrive 的物理根路径（Pester 管理的隔离临时目录，测试结束自动清理）
        [string]$Script:TestDriveRoot = (Get-PSDrive -Name TestDrive).Root

        # 日志函数 Mock：Write-LogEntry 为纯日志函数，全级别静默记录
        Mock Write-LogEntry -ModuleName IPAP { }

    }

    AfterAll {
        # 清理模块内配置实例与模块，防止污染其他测试
        InModuleScope IPAP { $script:IPAPConfigInstance = $null }
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常路径 - 完整目录树创建' {
        It '应在 TestDrive 下创建日期前缀项目目录并返回项目路径' {
            # 准备：基准目录与若干假图片文件（验证目录创建不影响既有文件）
            [string]$BaseDir = Join-Path $Script:TestDriveRoot 'base_normal'
            New-Item -ItemType Directory -Path $BaseDir | Out-Null
            Set-Content -LiteralPath (Join-Path $BaseDir 'a.jpg') -Value 'fake-image'
            Set-Content -LiteralPath (Join-Path $BaseDir 'b.png') -Value 'fake-image'

            # 构建期望的项目目录名（日期前缀 + 项目名，以源码格式为准）
            [string]$Today = Get-Date -Format 'yyyy-MM-dd'
            [string]$ExpectedProjectDir = Join-Path $BaseDir "${Today}_MangaNormal"

            [string]$Result = New-ProjectStructure -BaseDir $BaseDir -ProjectName 'MangaNormal'

            # 验证返回值与真实目录存在
            $Result | Should -Be $ExpectedProjectDir
            Test-Path -LiteralPath $ExpectedProjectDir -PathType Container | Should -BeTrue
            # 验证既有文件未被目录创建过程影响
            Test-Path -LiteralPath (Join-Path $BaseDir 'a.jpg') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $BaseDir 'b.png') | Should -BeTrue
        }

        It '应创建全部 6 个标准工作流子目录' {
            [string]$BaseDir = Join-Path $Script:TestDriveRoot 'base_tree'
            New-Item -ItemType Directory -Path $BaseDir | Out-Null

            [string]$ProjectDir = New-ProjectStructure -BaseDir $BaseDir -ProjectName 'MangaTree'

            # 标准子目录清单（以源码为准）
            [string[]]$SubDirs = @(
                '02_Preprocessing\raw_source',
                '02_Preprocessing\original_non_text_raw',
                '02_Preprocessing\inpainted',
                '02_Preprocessing\mask',
                '03_Typesetting\workfiles',
                '03_Typesetting\final_pages'
            )

            # 逐一验证子目录真实存在
            foreach ($subDir in $SubDirs)
            {
                Test-Path -LiteralPath (Join-Path $ProjectDir $subDir) -PathType Container | Should -BeTrue -Because "应创建子目录: $subDir"
            }
        }

        It '基准目录不存在时应级联创建 BaseDir 及完整目录树' {
            # 源码使用 New-Item -Force，缺失的 BaseDir 会被级联创建（以源码实际行为为准）
            [string]$BaseDir = Join-Path $Script:TestDriveRoot 'nested\auto_created_base'

            [string]$ProjectDir = New-ProjectStructure -BaseDir $BaseDir -ProjectName 'MangaAutoBase'

            $ProjectDir | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath (Join-Path $ProjectDir '02_Preprocessing\raw_source') -PathType Container | Should -BeTrue
        }
    }

    Context '幂等性 - 重复调用' {
        It '已存在的项目目录使用 -Force 重复调用时不报错且目录树完整' {
            [string]$BaseDir = Join-Path $Script:TestDriveRoot 'base_idempotent'
            New-Item -ItemType Directory -Path $BaseDir | Out-Null

            [string]$FirstRun = New-ProjectStructure -BaseDir $BaseDir -ProjectName 'MangaIdempotent' -Force
            [string]$SecondRun = New-ProjectStructure -BaseDir $BaseDir -ProjectName 'MangaIdempotent' -Force

            # 两次调用返回相同路径，目录树保持完整（2 个顶级分组 + 6 个工作流子目录 = 8 个）
            $SecondRun | Should -Be $FirstRun
            [int]$SubDirCount = (Get-ChildItem -LiteralPath $FirstRun -Recurse -Directory).Count
            $SubDirCount | Should -Be 8
        }
    }

    Context '失败路径' {
        It 'BaseDir 含 Windows 非法路径字符时应记录错误并抛出终止错误' {
            # 项目错误语义基于 $ErrorActionPreference = 'Stop'（见 build.ps1 与 Write-LogEntry 设计说明）：
            # Stop 环境下 New-Item 的非终止错误升级为终止错误，进入 catch 后由 Write-LogEntry -Level Error -Message 真实抛出
            [string]$BadBaseDir = Join-Path $Script:TestDriveRoot 'bad<>name'

            # 模块函数的 EAP 走模块作用域链（不受调用者局部 EAP 影响），必须设为全局才能传播进模块；
            # Stop 环境下 New-Item 的非终止错误升级为终止错误，进入 catch 后由 Write-LogEntry -Level Error -Message 真实抛出
            {
                $Global:ErrorActionPreference = 'Stop'
                try
                {
                    New-ProjectStructure -BaseDir $BadBaseDir -ProjectName 'MangaFail'
                }
                finally
                {
                    # 恢复全局错误偏好，避免污染 Pester 运行环境
                    $Global:ErrorActionPreference = 'Continue'
                }
            } | Should -Throw '*创建项目目录失败*'
        }
    }
}
