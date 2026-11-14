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
    L5 输出字段验证  —— Context 'L5 输出字段验证'

    本函数是 [OutputType([void])]，产物是 README.md 文本，因此 L5 的「输出字段」
    指 README.md 的每一行与每一个字段，一律用 Get-Content 行数组做精确断言。
    不要用 -Raw 配合 \r\n 分段：here-string 产生 LF，只有文件末尾可能出现 CRLF。

    本轮处置记录：
    1. 源码曾把 [switch]$NeedUpscale 声明为 Mandatory，使帮助文档写明的
       「省略则为 false」不可用（省略即绑定失败）；已去掉 Mandatory，测试保留省略写法。
    2. 源码 Out-File 未加 -NoNewline，导致文件尾部多一个空行；已修复，
       由「文件末尾不应有多余空行」用例钉住。
    3. BeforeEach 静默 Mock 内部日志函数 Write-LogEntry，与「只 Mock 模块外部依赖」
       规则的冲突已登记至 docs/将来要改的地方.md。
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
        # 每个用例独立的真实项目目录（TestDrive 由 Pester 托管）
        [string]$Script:TestProjectDir = New-Item -ItemType Directory -Path 'TestDrive:\test_project' |
            Select-Object -ExpandProperty FullName
        [string]$Script:ReadmePath = Join-Path $Script:TestProjectDir 'README.md'

        # 静默内部日志函数（纯噪声抑制，规则例外见 docs/将来要改的地方.md）
        Mock Write-LogEntry -ModuleName IPAP { }

        # 共享基础数据（人造，不读取真实磁盘内容）
        $Script:BaseParams = @{
            ProjectDir  = $Script:TestProjectDir
            ProjectName = 'TestProject'
            ImageCount  = 50
        }

        # 分级夹具：New-ReadmeFile 只消费 Image.FullName / LongEdge / YDIF 三个字段
        $Script:TextLevel1 = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\text_001.jpg' }; Level = 1; LongEdge = 3000; YDIF = 3.5 }
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\text_002.jpg' }; Level = 1; LongEdge = 2400; YDIF = 2.5 }
        )
        $Script:TextLevel2 = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\text_003.jpg' }; Level = 2; LongEdge = 1200; YDIF = 1.5 }
        )
        $Script:NonTextLevel1 = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\nt_001.jpg' }; Level = 1; LongEdge = 2000; YDIF = 3.2 }
        )
        $Script:NonTextLevel2 = @(
            [PSCustomObject]@{ Image = [PSCustomObject]@{ FullName = 'C:\fake\nt_002.jpg' }; Level = 2; LongEdge = 900; YDIF = 1.4 }
        )
    }

    AfterEach {
        if (Test-Path -LiteralPath $Script:TestProjectDir) {
            Remove-Item -LiteralPath $Script:TestProjectDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'L1 正常执行路径' {
        It '省略 -NeedUpscale 时应生成 README.md 并写入空白状态与 N/A 倍数' {
            New-ReadmeFile @Script:BaseParams

            Test-Path -LiteralPath $Script:ReadmePath | Should -BeTrue
            Get-Content -LiteralPath $Script:ReadmePath | Should -Contain '- 原始文件是否需要高清化: [ ]'
            Get-Content -LiteralPath $Script:ReadmePath | Should -Contain '- 使用高清化倍数: N/A'
        }

        It '指定 -NeedUpscale 时应写入 [X] 标记与倍数 2' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale

            Get-Content -LiteralPath $Script:ReadmePath | Should -Contain '- 原始文件是否需要高清化: [X]'
            Get-Content -LiteralPath $Script:ReadmePath | Should -Contain '- 使用高清化倍数: 2'
        }

        It '执行成功时不应有任何管道输出' {
            $Result = New-ReadmeFile @Script:BaseParams

            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'L2 异常流程' {
        It '项目目录不存在时应抛出 IOException 并保留内层 ArgumentException' {
            $Params = $Script:BaseParams.Clone()
            $Params.ProjectDir = 'TestDrive:\no_such_dir'
            $Thrown = $null

            try {
                New-ReadmeFile @Params
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.IO.IOException])
            $Thrown.Exception.Message | Should -BeLike '创建/覆盖 README.md 文件失败: 项目目录不存在: *'
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
            $Thrown.Exception.Message | Should -BeExactly '创建/覆盖 README.md 文件失败: Disk full'
            $Thrown.Exception.InnerException.Message | Should -BeExactly 'Disk full'
        }

        It '创建后无法验证文件存在时应抛出 IOException' {
            # 目录检查通过、README.md 校验失败
            Mock -ModuleName IPAP Test-Path { param($LiteralPath) return ($LiteralPath -eq $Script:TestProjectDir) }
            $Thrown = $null

            try {
                New-ReadmeFile @Script:BaseParams
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.IO.IOException])
            $Thrown.Exception.Message | Should -BeExactly '创建/覆盖 README.md 文件失败: 无法验证 README.md 文件创建'
        }

        It 'ProjectName 为空字符串时应被参数绑定拒绝' {
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName '' -ImageCount 50 } |
                Should -Throw '*ProjectName*'
        }
    }

    Context 'L3 参数契约与边界数据' {
        It 'ImageCount 为 0 时应如实写入 0 张' {
            $Params = $Script:BaseParams.Clone()
            $Params.ImageCount = 0

            New-ReadmeFile @Params

            Get-Content -LiteralPath $Script:ReadmePath | Should -Contain '- 原始文件数量: 0 张'
        }

        It 'UpscaleRatio 取下界 1 时应写入 1' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -UpscaleRatio 1

            Get-Content -LiteralPath $Script:ReadmePath | Should -Contain '- 使用高清化倍数: 1'
        }

        It 'UpscaleRatio 取上界 4 时应写入 4' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -UpscaleRatio 4

            Get-Content -LiteralPath $Script:ReadmePath | Should -Contain '- 使用高清化倍数: 4'
        }

        It 'BriefText 为空字符串时不应生成项目信息段' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -BriefText ''

            Get-Content -LiteralPath $Script:ReadmePath | Should -Not -Contain '## 项目信息'
        }

        It 'ProjectDir 含 [] 时应按字面路径写入而非通配符展开' {
            # New-Item 没有 -LiteralPath，用 .NET API 建字面名目录（含通配符字符 []）
            [string]$DriveRoot = Split-Path -Parent $Script:TestProjectDir
            [string]$LiteralDir = [System.IO.Directory]::CreateDirectory((Join-Path $DriveRoot 'proj[1]')).FullName
            [string]$LiteralReadme = Join-Path $LiteralDir 'README.md'

            New-ReadmeFile -ProjectDir $LiteralDir -ProjectName 'TestProject' -ImageCount 5

            Test-Path -LiteralPath $LiteralReadme | Should -BeTrue
            # 通配符语义下 [1] 被当字符类，指向 proj1，故 -Path 查不到
            Test-Path -Path $LiteralReadme | Should -BeFalse

            Remove-Item -LiteralPath $LiteralDir -Recurse -Force
        }

        It 'ProjectName 含中文与空格时应原样写入首行' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName '漫画 第 1 卷' -ImageCount 5

            $Today = Get-Date -Format 'yyyy-MM-dd'
            @(Get-Content -LiteralPath $Script:ReadmePath)[0] | Should -BeExactly "# 项目记录: 漫画 第 1 卷 ($Today)"
        }
    }

    Context 'L4 分支与循环' {
        It '-WhatIf 时不应创建文件、不应写日志且无输出' {
            $Result = New-ReadmeFile @Script:BaseParams -WhatIf

            $Result | Should -BeNullOrEmpty
            Test-Path -LiteralPath $Script:ReadmePath | Should -BeFalse
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 0 -Exactly
        }

        It '提供 BriefText 时应生成项目信息段并写入内容' {
            New-ReadmeFile @Script:BaseParams -BriefText '这是测试项目简介'

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '## 项目信息'
            $Lines | Should -Contain '这是测试项目简介'
        }

        It '四个分级数组全空时不应生成高清化详情段' {
            New-ReadmeFile @Script:BaseParams

            Get-Content -LiteralPath $Script:ReadmePath | Should -Not -Contain '## 高清化处理详情'
        }

        It '仅有文字图 Level 1 时应只生成有文字图 Level 1 表' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -Level1ImageLevels $Script:TextLevel1

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '### 有文字图'
            $Lines | Should -Contain '#### Level 1 (FFmpeg 锐化) - 2 张'
            $Lines | Should -Not -Contain '### 无文字图'
            $Lines | Should -Not -Contain '#### Level 2 (Real-CUGAN AI 超分) - 1 张'
        }

        It '仅有文字图 Level 2 时应只生成有文字图 Level 2 表' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -Level2ImageLevels $Script:TextLevel2

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '### 有文字图'
            $Lines | Should -Contain '#### Level 2 (Real-CUGAN AI 超分) - 1 张'
            $Lines | Should -Not -Contain '### 无文字图'
        }

        It '仅无文字图 Level 1 时应只生成无文字图 Level 1 表' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -NonTextLevel1ImageLevels $Script:NonTextLevel1

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '### 无文字图'
            $Lines | Should -Contain '#### Level 1 (FFmpeg 锐化) - 1 张'
            $Lines | Should -Not -Contain '### 有文字图'
        }

        It '仅无文字图 Level 2 时应只生成无文字图 Level 2 表' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -NonTextLevel2ImageLevels $Script:NonTextLevel2

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '### 无文字图'
            $Lines | Should -Contain '#### Level 2 (Real-CUGAN AI 超分) - 1 张'
            $Lines | Should -Not -Contain '### 有文字图'
        }

        It '四个分级数组全给时应生成两段四表' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale `
                -Level1ImageLevels $Script:TextLevel1 `
                -Level2ImageLevels $Script:TextLevel2 `
                -NonTextLevel1ImageLevels $Script:NonTextLevel1 `
                -NonTextLevel2ImageLevels $Script:NonTextLevel2

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '## 高清化处理详情'
            $Lines | Should -Contain '### 有文字图'
            $Lines | Should -Contain '### 无文字图'
            @($Lines | Where-Object { $PSItem -eq '#### Level 1 (FFmpeg 锐化) - 2 张' }).Count | Should -Be 1
            # 有文字图与无文字图各一张 Level 2 表
            @($Lines | Where-Object { $PSItem -eq '#### Level 2 (Real-CUGAN AI 超分) - 1 张' }).Count | Should -Be 2
        }
    }

    Context 'L5 输出字段验证' {
        BeforeEach {
            # 基线产物：无项目简介、无高清化详情，行号稳定
            New-ReadmeFile @Script:BaseParams
            $Script:Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
        }

        It '首行应包含项目名与当日日期' {
            $Today = Get-Date -Format 'yyyy-MM-dd'

            $Script:Lines[0] | Should -BeExactly "# 项目记录: TestProject ($Today)"
            $Script:Lines[1] | Should -BeExactly ''
            $Script:Lines[2] | Should -BeExactly '## 项目基本信息'
        }

        It '项目基本信息三行应逐行精确' {
            $Script:Lines[3] | Should -BeExactly '- 原始文件数量: 50 张'
            $Script:Lines[4] | Should -BeExactly '- 原始文件是否需要高清化: [ ]'
            $Script:Lines[5] | Should -BeExactly '- 使用高清化倍数: N/A'
        }

        It '进度跟踪标题与六个复选项应逐行精确' {
            $Script:Lines[7] | Should -BeExactly '## 进度跟踪'
            $Script:Lines[8] | Should -BeExactly '- [ ] 文件整理与分离'
            $Script:Lines[9] | Should -BeExactly '- [ ] OCR 处理与校对'
            $Script:Lines[10] | Should -BeExactly '- [ ] Inpainting 处理与修正'
            $Script:Lines[11] | Should -BeExactly '- [ ] 文本翻译'
            $Script:Lines[12] | Should -BeExactly '- [ ] 嵌字 (完成至页 X)'
            $Script:Lines[13] | Should -BeExactly '- [ ] 最终质量检查'
        }

        It '处理笔记段标题与三个子标题应逐行精确' {
            $Script:Lines[15] | Should -BeExactly '## 处理笔记与特殊情况'
            $Script:Lines[16] | Should -BeExactly '### 预处理阶段'
            $Script:Lines[18] | Should -BeExactly '### 翻译阶段'
            $Script:Lines[20] | Should -BeExactly '### 嵌字阶段'
        }

        It '待办与其他段的标题与占位行应逐行精确' {
            $Script:Lines[22] | Should -BeExactly '## 待办/提醒'
            $Script:Lines[24] | Should -BeExactly '## 其他'
            $Script:Lines[25] | Should -BeExactly '- [任何你想记下的其他信息]'
        }

        It '文件末尾不应有多余空行' {
            $Script:Lines.Count | Should -Be 26
            $Script:Lines[-1] | Should -BeExactly '- [任何你想记下的其他信息]'
        }

        It '详情表的表头与分隔行应逐行精确' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -Level1ImageLevels $Script:TextLevel1

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '| 文件名 | 长边分辨率 | YDIF |'
            $Lines | Should -Contain '|--------|-----------|------|'
            $Lines | Should -Contain '#### Level 1 (FFmpeg 锐化) - 2 张'
        }

        It '详情表每一行的文件名、长边、YDIF 三字段应精确' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale -Level1ImageLevels $Script:TextLevel1

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '| text_001.jpg | 3000px | 3.5 |'
            $Lines | Should -Contain '| text_002.jpg | 2400px | 2.5 |'
        }

        It '四类详情的小标题计数与无文字图字段应精确' {
            New-ReadmeFile @Script:BaseParams -NeedUpscale `
                -Level1ImageLevels $Script:TextLevel1 `
                -Level2ImageLevels $Script:TextLevel2 `
                -NonTextLevel1ImageLevels $Script:NonTextLevel1 `
                -NonTextLevel2ImageLevels $Script:NonTextLevel2

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '#### Level 1 (FFmpeg 锐化) - 2 张'
            $Lines | Should -Contain '#### Level 2 (Real-CUGAN AI 超分) - 1 张'
            $Lines | Should -Contain '| nt_001.jpg | 2000px | 3.2 |'
            $Lines | Should -Contain '| nt_002.jpg | 900px | 1.4 |'
        }
    }
}
