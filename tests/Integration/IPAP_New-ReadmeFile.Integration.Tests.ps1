#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - New-ReadmeFile 集成测试
.DESCRIPTION
    使用 Pester TestDrive 提供的真实文件系统，验证 New-ReadmeFile 与
    文件系统的协作行为：README.md 真实生成、模板关键行内容精确匹配、
    重复调用覆盖旧文件、失败守卫路径。
    统一使用 TestDrive 的物理根路径（Pester 管理的隔离临时目录）进行文件操作，
    规避内容写入 cmdlet 对 PSDrive 前缀路径的解析兼容性问题。
    不涉及任何外部工具（FFmpeg/FFprobe/Real-CUGAN）的真实执行。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'New-ReadmeFile 集成测试（真实文件系统协作）' -Tag 'Integration' {
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
        # 清理全局配置实例与模块，防止污染其他测试
        $Global:IPAPConfigInstance = $null
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常路径 - README.md 生成' {
        It '应在项目目录真实生成 README.md 且包含需要高清化的关键模板行' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_upscale'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectName 'TestProject' -ImageCount 42 -NeedUpscale -UpscaleRatio 2

            # 验证文件真实生成
            [string]$ReadmePath = Join-Path $ProjectDir 'README.md'
            Test-Path -LiteralPath $ReadmePath -PathType Leaf | Should -BeTrue

            # 逐行验证模板关键行（完整行精确匹配，以源码模板为准）
            [string[]]$Lines = Get-Content -LiteralPath $ReadmePath
            ($Lines | Where-Object { $PSItem -match '^# 项目记录: TestProject \(\d{4}-\d{2}-\d{2}\)$' }) | Should -Not -BeNullOrEmpty
            $Lines | Should -Contain '- 原始文件数量: 42 张'
            $Lines | Should -Contain '- 原始文件是否需要高清化: [X]'
            $Lines | Should -Contain '- 使用高清化倍数: 2'
            $Lines | Should -Contain '- [ ] 文件整理与分离'
            $Lines | Should -Contain '- [ ] 最终质量检查'
        }

        It '不需要高清化时应写入空白状态占位与 N/A 倍数' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_no_upscale'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectName 'PlainProject' -ImageCount 3

            [string[]]$Lines = Get-Content -LiteralPath (Join-Path $ProjectDir 'README.md')
            $Lines | Should -Contain '- 原始文件数量: 3 张'
            $Lines | Should -Contain '- 原始文件是否需要高清化: [ ]'
            $Lines | Should -Contain '- 使用高清化倍数: N/A'
        }

        It '提供 BriefText 时应真实写入项目信息段落' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_brief'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectName 'BriefProject' -ImageCount 5 -BriefText '这是测试项目简介'

            [string[]]$Lines = Get-Content -LiteralPath (Join-Path $ProjectDir 'README.md')
            $Lines | Should -Contain '## 项目信息'
            $Lines | Should -Contain '这是测试项目简介'
        }
    }

    Context '覆盖写入' {
        It '再次调用应覆盖旧 README.md 的全部内容' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_overwrite'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null

            # 预先放置旧内容，验证覆盖行为
            Set-Content -LiteralPath (Join-Path $ProjectDir 'README.md') -Value 'OLD-STALE-CONTENT-MARKER'

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectName 'OverwriteProject' -ImageCount 7

            [string[]]$Lines = Get-Content -LiteralPath (Join-Path $ProjectDir 'README.md')
            # 旧内容消失且新模板生效
            ($Lines | Where-Object { $PSItem -match 'OLD-STALE-CONTENT-MARKER' }) | Should -BeNullOrEmpty
            $Lines | Should -Contain '- 原始文件数量: 7 张'
            ($Lines | Where-Object { $PSItem -match '^# 项目记录: OverwriteProject \(\d{4}-\d{2}-\d{2}\)$' }) | Should -Not -BeNullOrEmpty
        }
    }

    Context '失败路径' {
        It '项目目录不存在时应记录错误并抛出终止错误' {
            [string]$MissingDir = Join-Path $Script:TestDriveRoot 'no_such_project_dir'

            { New-ReadmeFile -ProjectDir $MissingDir -ProjectName 'X' -ImageCount 1 -NeedUpscale } | Should -Throw '*项目目录不存在*'
        }
    }
}
