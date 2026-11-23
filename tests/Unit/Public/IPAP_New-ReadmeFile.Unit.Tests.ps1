#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - New-ReadmeFile 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖 New-ReadmeFile 的全部分支与输出字段：
    L1 正常流程      —— Context 'L1 正常执行路径'
    L2 异常流程      —— Context 'L2 异常流程'
    L3 边界数据      —— Context 'L3 参数契约与边界数据'
    L4 分支与循环    —— Context 'L4 分支与循环'
    L5 输出契约验证  —— Context 'L5 输出契约验证'

    本函数 [OutputType([void])]，产物是 README.toml，因此 L5 的「输出契约」
    指文件能被 TOML 解析器读回、且各段字段值与入参一致。
    断言一律走 ConvertFrom-Toml 回读，不断言具体行号——TOML 注释行会随文案调整而移动。

    2026-11-23 起的契约：
    - 文件名 README.toml，替代原 README.md；
    - [run].status 承担运行状态（running / done），替代原 .ipap-run.json；
    - [project] 段为 config.toml 的只读副本，由调用方传入原始字段；
    - [progress] / [notes] / [todo] / [misc] 为手工段，重新生成时从旧文件读回并保留。

    BeforeEach 静默 Mock 内部日志函数 Write-LogEntry，与「只 Mock 模块外部依赖」
    规则的冲突已登记至 docs/将来要改的地方.md。
#>

Describe 'New-ReadmeFile Unit Tests' -Tag 'New-ReadmeFile', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
        # 断言要用 TOML 解析器回读，显式导入避免依赖被测函数顺手导入的副作用
        Import-Module (Join-Path $ProjectRoot 'output\RequiredModules\PSToml') -Force -Global

        # 统一回读入口：任何断言都先走 TOML 解析，避免把「文件里有这行字」当作字段正确
        function Get-ParsedReadme {
            param (
                [Parameter(Mandatory = $true)]
                [string]$Path
            )

            return ConvertFrom-Toml -InputObject ([System.IO.File]::ReadAllText($Path))
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 每个用例独立的真实项目目录（TestDrive 由 Pester 托管）
        [string]$Script:TestProjectDir = New-Item -ItemType Directory -Path 'TestDrive:\test_project' |
            Select-Object -ExpandProperty FullName
        [string]$Script:ReadmePath = Join-Path $Script:TestProjectDir 'README.toml'

        # 静默内部日志函数（纯噪声抑制，规则例外见 docs/将来要改的地方.md）
        Mock Write-LogEntry -ModuleName IPAP { }

        # 基线：Level 1 项目，两个有文字图 + 一个无文字图，单图等级全部与项目一致（无异类页）
        $Script:BaseParams = @{
            ProjectDir   = $Script:TestProjectDir
            ProjectLevel = 1
            Status       = 'running'
            Author       = 'TestAuthor'
            OriginalTitle = 'TestTitle'
        }

        $Script:TextLevel1 = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\text_001.jpg' }; Level = 1; LongEdge = 3000; YDIF = 3.5 }
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\text_002.jpg' }; Level = 1; LongEdge = 2400; YDIF = 2.5 }
        )
        $Script:NonTextLevel1 = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\nt_001.jpg' }; Level = 1; LongEdge = 1920; YDIF = 8.75 }
        )

        # 异类页夹具：项目 Level 1，但夹杂 Level 0 与 Level 2 的单图
        $Script:TextMixed = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\text_001.jpg' }; Level = 1; LongEdge = 3000; YDIF = 3.5 }
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\cover_000.jpg' }; Level = 0; LongEdge = 560; YDIF = 61.14 }
        )
        $Script:NonTextMixed = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\nt_009.jpg' }; Level = 2; LongEdge = 900; YDIF = 1.4 }
        )
    }

    AfterEach {
        if (Test-Path -LiteralPath $Script:TestProjectDir) {
            Remove-Item -LiteralPath $Script:TestProjectDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'L1 正常执行路径' {
        It 'Level 0 项目应写入 upscale_ratio = 1.0' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectLevel 0 -Status 'running' -TextImageLevels $Script:TextLevel1

            $Readme = Get-ParsedReadme -Path $Script:ReadmePath
            $Readme.summary.upscale_ratio | Should -Be 1.0
            $Readme.run.project_level | Should -Be 0
        }

        It 'Level 1 项目应写入 upscale_ratio = 1.2' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextLevel1

            (Get-ParsedReadme -Path $Script:ReadmePath).summary.upscale_ratio | Should -Be 1.2
        }

        It 'Level 2 项目应按 -RealCuganScale 写入倍数' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectLevel 2 -Status 'running' -RealCuganScale 4 -TextImageLevels $Script:TextLevel1

            $Readme = Get-ParsedReadme -Path $Script:ReadmePath
            $Readme.summary.upscale_ratio | Should -Be 4.0
            $Readme.run.realcugan_scale | Should -Be 4
        }

        It '张数应按两个分级数组派生' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextLevel1

            $Readme = Get-ParsedReadme -Path $Script:ReadmePath
            $Readme.summary.text_count | Should -Be 2
            $Readme.summary.non_text_count | Should -Be 1
            $Readme.summary.total_count | Should -Be 3
        }

        It '执行成功时不应有任何管道输出' {
            $Result = New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1

            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'L2 异常流程' {
        It '项目目录不存在时应抛出 IOException 并保留内层 ArgumentException' {
            $Thrown = $null

            try {
                New-ReadmeFile -ProjectDir 'TestDrive:\no_such_dir' -ProjectLevel 0 -Status 'running'
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.IO.IOException])
            $Thrown.Exception.Message | Should -BeLike '创建/覆盖 README.toml 文件失败: 项目目录不存在: *'
            $Thrown.Exception.InnerException | Should -BeOfType ([System.ArgumentException])
            # 内层记录现场 1 次 + 外层 catch 记录上下文 1 次
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' } -Times 2 -Exactly
        }

        It '写入文件失败时应包装为 IOException 并保留原始消息' {
            Mock -ModuleName IPAP Out-File { throw 'Disk full' }
            $Thrown = $null

            try {
                New-ReadmeFile @Script:BaseParams
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.IO.IOException])
            $Thrown.Exception.Message | Should -BeExactly '创建/覆盖 README.toml 文件失败: Disk full'
            $Thrown.Exception.InnerException.Message | Should -BeExactly 'Disk full'
        }

        It '创建后无法验证文件存在时应抛出 IOException' {
            # 目录检查通过、README.toml 校验失败
            Mock -ModuleName IPAP Test-Path { param($LiteralPath) return ($LiteralPath -eq $Script:TestProjectDir) }
            $Thrown = $null

            try {
                New-ReadmeFile @Script:BaseParams
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.IO.IOException])
            $Thrown.Exception.Message | Should -BeExactly '创建/覆盖 README.toml 文件失败: 无法验证 README.toml 文件创建'
        }

        It 'ProjectLevel 超出 0-2 时应被 ValidateRange 拒绝' {
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectLevel 3 -Status 'running' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'RealCuganScale 超出 1-4 时应被 ValidateRange 拒绝' {
            { New-ReadmeFile @Script:BaseParams -RealCuganScale 5 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'Status 不是 running/done 时应被 ValidateSet 拒绝' {
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectLevel 0 -Status 'paused' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }
    }

    Context 'L3 参数契约与边界数据' {
        It '两个分级数组都为空时应写入 0 张且不生成 [level] 段' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectLevel 0 -Status 'running'

            $Readme = Get-ParsedReadme -Path $Script:ReadmePath
            $Readme.summary.total_count | Should -Be 0
            $Readme.Keys | Should -Not -Contain 'level'
        }

        It 'RealCuganScale 取下界 1 应被接受' {
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectLevel 2 -Status 'running' -RealCuganScale 1 } |
                Should -Not -Throw
        }

        It 'RealCuganScale 取上界 4 应被接受' {
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectLevel 2 -Status 'running' -RealCuganScale 4 } |
                Should -Not -Throw
        }

        It '简介为空时应写入空字符串而非报错' {
            New-ReadmeFile @Script:BaseParams -OriginalOverview '' -ChineseOverview ''

            $Readme = Get-ParsedReadme -Path $Script:ReadmePath
            $Readme.project.original_overview | Should -BeExactly ''
            $Readme.project.chinese_overview | Should -BeExactly ''
        }

        It 'ProjectDir 含 [] 时应按字面路径写入而非通配符展开' {
            # New-Item 没有 -LiteralPath，用 .NET API 建字面名目录（含通配符字符 []）
            [string]$DriveRoot = Split-Path -Parent $Script:TestProjectDir
            [string]$LiteralDir = [System.IO.Directory]::CreateDirectory((Join-Path $DriveRoot 'proj[1]')).FullName
            [string]$LiteralReadme = Join-Path $LiteralDir 'README.toml'

            New-ReadmeFile -ProjectDir $LiteralDir -ProjectLevel 0 -Status 'running'

            Test-Path -LiteralPath $LiteralReadme | Should -BeTrue
            # 通配符语义下 [1] 被当字符类，指向 proj1，故 -Path 查不到
            Test-Path -Path $LiteralReadme | Should -BeFalse

            Remove-Item -LiteralPath $LiteralDir -Recurse -Force
        }

        It '标题含引号与反斜杠时应原样回读' {
            New-ReadmeFile @Script:BaseParams -Author 'A"B\C' -OriginalTitle "第 1 卷`t测试"

            $Readme = Get-ParsedReadme -Path $Script:ReadmePath
            $Readme.project.author | Should -BeExactly 'A"B\C'
            $Readme.project.original_title | Should -BeExactly "第 1 卷`t测试"
        }

        It '简介含三连单引号时应改用双引号字符串并原样回读' {
            [string]$Tricky = "第一行`n''' 三连引号`n第三行"
            New-ReadmeFile @Script:BaseParams -OriginalOverview $Tricky

            (Get-ParsedReadme -Path $Script:ReadmePath).project.original_overview | Should -BeExactly $Tricky
        }

        It '简介以单引号结尾时应改用双引号字符串并原样回读' {
            [string]$Tricky = "结尾带单引号'"
            New-ReadmeFile @Script:BaseParams -ChineseOverview $Tricky

            (Get-ParsedReadme -Path $Script:ReadmePath).project.chinese_overview | Should -BeExactly $Tricky
        }
    }

    Context 'L4 分支与循环' {
        It '-WhatIf 时不应创建文件、不应写日志且无输出' {
            $Result = New-ReadmeFile @Script:BaseParams -WhatIf

            $Result | Should -BeNullOrEmpty
            Test-Path -LiteralPath $Script:ReadmePath | Should -BeFalse
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 0 -Exactly
        }

        It '全部页面与项目等级一致时不应生成 [[outliers]]' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextLevel1

            (Get-ParsedReadme -Path $Script:ReadmePath).Keys | Should -Not -Contain 'outliers'
        }

        It '有文字图存在异类页时应记入 [[outliers]] 并标注类别' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextMixed

            $Outliers = @((Get-ParsedReadme -Path $Script:ReadmePath).outliers)
            $Outliers.Count | Should -Be 1
            $Outliers[0].file | Should -BeExactly 'cover_000.jpg'
            $Outliers[0].category | Should -BeExactly '有文字图'
            $Outliers[0].level | Should -Be 0
        }

        It '仅无文字图存在异类页时类别应为无文字图' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextMixed

            $Outliers = @((Get-ParsedReadme -Path $Script:ReadmePath).outliers)
            $Outliers.Count | Should -Be 1
            $Outliers[0].category | Should -BeExactly '无文字图'
        }

        It '两类都有异类页时应合并写入两条' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextMixed -NonTextImageLevels $Script:NonTextMixed

            $Outliers = @((Get-ParsedReadme -Path $Script:ReadmePath).outliers)
            $Outliers.Count | Should -Be 2
            @($Outliers | Where-Object { $PSItem.category -eq '有文字图' }).Count | Should -Be 1
            @($Outliers | Where-Object { $PSItem.category -eq '无文字图' }).Count | Should -Be 1
        }

        It '只有无文字图时不应生成 [level.text]' {
            New-ReadmeFile @Script:BaseParams -NonTextImageLevels $Script:NonTextLevel1

            $Readme = Get-ParsedReadme -Path $Script:ReadmePath
            $Readme.level.Keys | Should -Contain 'non_text'
            $Readme.level.Keys | Should -Not -Contain 'text'
        }

        It '旧文件的手工段应原样保留' {
            [string]$Previous = @'
[progress]
organize = true
ocr = false
inpainting = false
translate = false
typeset_page = 37
final_check = false

[notes]
preprocessing = '''
旧笔记'''
translate = '''
'''
typeset = '''
'''

[todo]
items = ["补第 12 页拟声词"]

[misc]
items = ["封面待定"]
'@
            Set-Content -LiteralPath $Script:ReadmePath -Value $Previous -Encoding utf8

            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1

            $Readme = Get-ParsedReadme -Path $Script:ReadmePath
            $Readme.progress.organize | Should -BeTrue
            $Readme.progress.typeset_page | Should -Be 37
            $Readme.notes.preprocessing | Should -BeExactly "旧笔记"
            @($Readme.todo.items) | Should -Be @('补第 12 页拟声词')
            @($Readme.misc.items) | Should -Be @('封面待定')
        }

        It '旧文件未收尾时应沿用 started_at' {
            New-ReadmeFile @Script:BaseParams
            [string]$FirstStartedAt = (Get-ParsedReadme -Path $Script:ReadmePath).run.started_at

            Start-Sleep -Milliseconds 20
            New-ReadmeFile @Script:BaseParams -Status 'done'

            (Get-ParsedReadme -Path $Script:ReadmePath).run.started_at | Should -BeExactly $FirstStartedAt
        }

        It '旧文件已收尾时应重新生成 started_at' {
            New-ReadmeFile @Script:BaseParams
            New-ReadmeFile @Script:BaseParams -Status 'done'
            [string]$DoneStartedAt = (Get-ParsedReadme -Path $Script:ReadmePath).run.started_at

            Start-Sleep -Milliseconds 20
            New-ReadmeFile @Script:BaseParams

            (Get-ParsedReadme -Path $Script:ReadmePath).run.started_at | Should -Not -BeExactly $DoneStartedAt
        }
    }

    Context 'L5 输出契约验证' {
        BeforeEach {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextLevel1
            $Script:Readme = Get-ParsedReadme -Path $Script:ReadmePath
        }

        It '文件应能被 TOML 解析且 [project] 为第一个表' {
            [string[]]$Lines = Get-Content -LiteralPath $Script:ReadmePath -Encoding UTF8
            $FirstTable = @($Lines | Where-Object { $PSItem -match '^\[[^\[]' })[0]
            $FirstTable | Should -BeExactly '[project]'
        }

        It '[project] 段应回读全部五个配置字段' {
            $Script:Readme.project.author | Should -BeExactly 'TestAuthor'
            $Script:Readme.project.original_title | Should -BeExactly 'TestTitle'
            $Script:Readme.project.chinese_title | Should -BeExactly ''
            $Script:Readme.project.original_overview | Should -BeExactly ''
        }

        It '[run] 段应含运行状态与参数变更检测所需字段' {
            $Script:Readme.run.status | Should -BeExactly 'running'
            $Script:Readme.run.project_level | Should -Be 1
            $Script:Readme.run.realcugan_scale | Should -Be 2
            $Script:Readme.run.model | Should -BeExactly ''
            { [datetime]::Parse($Script:Readme.run.started_at) } | Should -Not -Throw
        }

        It '[level] 段的长边与 YDIF 应取自分级结果' {
            $Script:Readme.level.text.count | Should -Be 2
            $Script:Readme.level.text.long_edge_min | Should -Be 2400
            $Script:Readme.level.text.long_edge_max | Should -Be 3000
            $Script:Readme.level.text.ydif_min | Should -Be 2.5
            $Script:Readme.level.text.ydif_max | Should -Be 3.5
            $Script:Readme.level.non_text.long_edge_min | Should -Be 1920
        }

        It '手工段默认值应逐项精确' {
            $Script:Readme.progress.organize | Should -BeFalse
            $Script:Readme.progress.ocr | Should -BeFalse
            $Script:Readme.progress.inpainting | Should -BeFalse
            $Script:Readme.progress.translate | Should -BeFalse
            $Script:Readme.progress.typeset_page | Should -Be 0
            $Script:Readme.progress.final_check | Should -BeFalse
            @($Script:Readme.todo.items).Count | Should -Be 0
            @($Script:Readme.misc.items).Count | Should -Be 0
        }

        It '文件末尾不应有多余空行' {
            [string[]]$Lines = Get-Content -LiteralPath $Script:ReadmePath -Encoding UTF8

            $Lines[-1] | Should -Not -BeExactly ''
        }
    }
}
