#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - New-ReadmeFile 集成测试
.DESCRIPTION
    使用 Pester TestDrive 提供的真实文件系统，验证 New-ReadmeFile 与文件系统的协作行为：
    README.toml 真实生成、可被 TOML 解析器读回、重复调用覆盖自动段但保留手工段、
    旧文件损坏时先备份再重建、失败守卫路径。
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
        Import-Module (Join-Path $ProjectRoot 'output\RequiredModules\PSToml') -Force -Global

        # TestDrive 的物理根路径（Pester 管理的隔离临时目录，测试结束自动清理）
        [string]$Script:TestDriveRoot = (Get-PSDrive -Name TestDrive).Root

        # 分级夹具：只需 Image.FullName / Level / LongEdge / YDIF 四个字段
        $Script:TextLevels = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\page_001.jpg' }; Level = 1; LongEdge = 2400; YDIF = 4.2 }
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\page_002.jpg' }; Level = 0; LongEdge = 1920; YDIF = 9.1 }
        )
        $Script:NonTextLevels = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\bg_001.jpg' }; Level = 1; LongEdge = 1700; YDIF = 8.8 }
        )
    }

    AfterAll {
        # 清理模块内配置实例与模块，防止污染其他测试
        InModuleScope IPAP { $script:IPAPConfigInstance = $null }
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 日志函数 Mock：Write-LogEntry 为纯日志函数，全级别静默记录
        Mock Write-LogEntry -ModuleName IPAP { }
    }

    Context '正常路径 - README.toml 生成' {
        It '应真实生成 README.toml 且张数、等级、倍数可由 TOML 读回' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_upscale'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectLevel 1 -Status 'running' `
                -TextImageLevels $Script:TextLevels -NonTextImageLevels $Script:NonTextLevels -RealCuganScale 2

            [string]$ReadmePath = Join-Path $ProjectDir 'README.toml'
            Test-Path -LiteralPath $ReadmePath -PathType Leaf | Should -BeTrue

            $Readme = ConvertFrom-Toml -InputObject ([System.IO.File]::ReadAllText($ReadmePath))
            $Readme.summary.text_count | Should -Be 2
            $Readme.summary.non_text_count | Should -Be 1
            $Readme.summary.total_count | Should -Be 3
            $Readme.summary.upscale_ratio | Should -Be 1.2
            $Readme.run.status | Should -BeExactly 'running'
        }

        It 'Level 0 项目应写入 1.0 倍数并列出异类页' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_no_upscale'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectLevel 0 -Status 'running' -TextImageLevels $Script:TextLevels

            $Readme = ConvertFrom-Toml -InputObject ([System.IO.File]::ReadAllText((Join-Path $ProjectDir 'README.toml')))
            $Readme.summary.upscale_ratio | Should -Be 1.0
            # page_001 单图判 Level 1，与项目 Level 0 不一致，应出现在异类页
            $Outliers = @($Readme.outliers)
            $Outliers.Count | Should -Be 1
            $Outliers[0].file | Should -BeExactly 'page_001.jpg'
        }

        It '项目信息字段应真实写入并可读回' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_project'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectLevel 0 -Status 'running' `
                -Author '某作者' -OriginalTitle '原作品名' -ChineseTitle '中文译名' `
                -OriginalOverview "原文第一行`n原文第二行" -ChineseOverview '中文简介'

            $Readme = ConvertFrom-Toml -InputObject ([System.IO.File]::ReadAllText((Join-Path $ProjectDir 'README.toml')))
            $Readme.project.author | Should -BeExactly '某作者'
            $Readme.project.original_title | Should -BeExactly '原作品名'
            $Readme.project.chinese_title | Should -BeExactly '中文译名'
            $Readme.project.original_overview | Should -BeExactly "原文第一行`n原文第二行"
            $Readme.project.chinese_overview | Should -BeExactly '中文简介'
        }
    }

    Context '覆盖写入' {
        It '再次调用应覆盖自动段但保留手工维护的进度与笔记' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_overwrite'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null
            [string]$ReadmePath = Join-Path $ProjectDir 'README.toml'

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectLevel 0 -Status 'running'
            # 模拟用户手工勾选进度、写笔记、加待办
            [string]$Edited = [System.IO.File]::ReadAllText($ReadmePath)
            $Edited = $Edited.Replace('organize     = false', 'organize     = true')
            $Edited = $Edited.Replace("preprocessing = '''`n'''", "preprocessing = '''`n人工笔记`n'''")
            $Edited = $Edited.Replace('[todo]' + "`n" + '# 每条一个字符串，例如 items = ["补第 12 页拟声词"]' + "`n" + 'items = []',
                '[todo]' + "`n" + 'items = ["补第 12 页拟声词"]')
            [System.IO.File]::WriteAllText($ReadmePath, $Edited, [Text.UTF8Encoding]::new($false))

            New-ReadmeFile -ProjectDir $ProjectDir -ProjectLevel 0 -Status 'done'

            $Readme = ConvertFrom-Toml -InputObject ([System.IO.File]::ReadAllText($ReadmePath))
            $Readme.run.status | Should -BeExactly 'done'
            $Readme.progress.organize | Should -BeTrue
            $Readme.notes.preprocessing | Should -BeExactly "人工笔记`n"
            @($Readme.todo.items) | Should -Be @('补第 12 页拟声词')
            # 自动段按最新结果重写：本次没传分级数组，张数归零
            $Readme.summary.total_count | Should -Be 0
        }

        It '旧文件损坏时应先备份为 .bad 再重建，且不抛异常' {
            [string]$ProjectDir = Join-Path $Script:TestDriveRoot 'readme_broken'
            New-Item -ItemType Directory -Path $ProjectDir | Out-Null
            [string]$ReadmePath = Join-Path $ProjectDir 'README.toml'
            Set-Content -LiteralPath $ReadmePath -Value '[run' -Encoding utf8

            { New-ReadmeFile -ProjectDir $ProjectDir -ProjectLevel 0 -Status 'running' } | Should -Not -Throw

            Test-Path -LiteralPath "$ReadmePath.bad" | Should -BeTrue
            # 新文件可用
            $Readme = ConvertFrom-Toml -InputObject ([System.IO.File]::ReadAllText($ReadmePath))
            $Readme.run.status | Should -BeExactly 'running'
        }
    }

    Context '失败路径' {
        It '项目目录不存在时应记录错误并抛出终止错误' {
            [string]$MissingDir = Join-Path $Script:TestDriveRoot 'no_such_project_dir'

            { New-ReadmeFile -ProjectDir $MissingDir -ProjectLevel 1 -Status 'running' } |
                Should -Throw '*项目目录不存在*'
        }
    }
}
