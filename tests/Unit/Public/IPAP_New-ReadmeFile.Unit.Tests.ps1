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

    重构后（2026-11-17）的契约：
    - 张数、统一等级、是否需要高清化、倍数全部由 -ProjectLevel 与分级数组派生，
      调用方不再传 -ImageCount / -NeedUpscale / -UpscaleRatio；
    - 预处理详情只列单图等级与项目等级不一致的「异类页」，不再逐页铺表。

    BeforeEach 静默 Mock 内部日志函数 Write-LogEntry，与「只 Mock 模块外部依赖」
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

        # 基线：Level 1 项目，两个有文字图 + 一个无文字图，单图等级全部与项目一致（无异类页）
        $Script:BaseParams = @{
            ProjectDir   = $Script:TestProjectDir
            ProjectName  = 'TestProject'
            ProjectLevel = 1
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
        It 'Level 0 项目应写入空白高清化状态与 N/A 倍数' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ProjectLevel 0 -TextImageLevels $Script:TextLevel1

            $Lines = Get-Content -LiteralPath $Script:ReadmePath
            $Lines | Should -Contain '- 项目统一等级: Level 0（已高清，不放大）'
            $Lines | Should -Contain '- 原始文件是否需要高清化: [ ]'
            $Lines | Should -Contain '- 使用高清化倍数: N/A'
        }

        It 'Level 1 项目应写入 [X] 与 1.2 倍' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextLevel1

            $Lines = Get-Content -LiteralPath $Script:ReadmePath
            $Lines | Should -Contain '- 项目统一等级: Level 1（FFmpeg 1.2 倍放大 + 锐化）'
            $Lines | Should -Contain '- 原始文件是否需要高清化: [X]'
            $Lines | Should -Contain '- 使用高清化倍数: 1.2'
        }

        It 'Level 2 项目应按 -RealCuganScale 写入倍数与等级文案' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ProjectLevel 2 `
                -RealCuganScale 4 -TextImageLevels $Script:TextLevel1

            $Lines = Get-Content -LiteralPath $Script:ReadmePath
            $Lines | Should -Contain '- 项目统一等级: Level 2（Real-CUGAN 4 倍超分）'
            $Lines | Should -Contain '- 使用高清化倍数: 4'
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
                New-ReadmeFile -ProjectDir 'TestDrive:\no_such_dir' -ProjectName 'TestProject' -ProjectLevel 0
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
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName '' -ProjectLevel 0 } |
                Should -Throw '*ProjectName*'
        }

        It 'ProjectLevel 超出 0-2 时应被 ValidateRange 拒绝' {
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'X' -ProjectLevel 3 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'RealCuganScale 超出 1-4 时应被 ValidateRange 拒绝' {
            { New-ReadmeFile @Script:BaseParams -RealCuganScale 5 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }
    }

    Context 'L3 参数契约与边界数据' {
        It '两个分级数组都为空时应写入 0 张且不生成预处理详情段' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ProjectLevel 0

            $Lines = Get-Content -LiteralPath $Script:ReadmePath
            $Lines | Should -Contain '- 有文字图: 0 张'
            $Lines | Should -Contain '- 无文字图: 0 张'
            $Lines | Should -Contain '- 合计: 0 张'
            $Lines | Should -Not -Contain '## 预处理详情'
        }

        It 'RealCuganScale 取下界 1 应被接受' {
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'X' -ProjectLevel 2 -RealCuganScale 1 } |
                Should -Not -Throw
        }

        It 'RealCuganScale 取上界 4 应被接受' {
            { New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'X' -ProjectLevel 2 -RealCuganScale 4 } |
                Should -Not -Throw
        }

        It 'BriefText 为空字符串时不应生成项目信息段' {
            New-ReadmeFile @Script:BaseParams -BriefText ''

            Get-Content -LiteralPath $Script:ReadmePath | Should -Not -Contain '## 项目信息'
        }

        It 'ProjectDir 含 [] 时应按字面路径写入而非通配符展开' {
            # New-Item 没有 -LiteralPath，用 .NET API 建字面名目录（含通配符字符 []）
            [string]$DriveRoot = Split-Path -Parent $Script:TestProjectDir
            [string]$LiteralDir = [System.IO.Directory]::CreateDirectory((Join-Path $DriveRoot 'proj[1]')).FullName
            [string]$LiteralReadme = Join-Path $LiteralDir 'README.md'

            New-ReadmeFile -ProjectDir $LiteralDir -ProjectName 'TestProject' -ProjectLevel 0

            Test-Path -LiteralPath $LiteralReadme | Should -BeTrue
            # 通配符语义下 [1] 被当字符类，指向 proj1，故 -Path 查不到
            Test-Path -Path $LiteralReadme | Should -BeFalse

            Remove-Item -LiteralPath $LiteralDir -Recurse -Force
        }

        It 'ProjectName 含中文与空格时应原样写入首行' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName '漫画 第 1 卷' -ProjectLevel 0

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

        It '全部页面与项目等级一致时不应生成异类页表' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextLevel1

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '## 预处理详情'
            $Lines | Should -Not -Contain '### 与项目等级不一致的页面（1 张）'
            $Lines | Should -Not -Contain '| 文件名 | 类别 | 单图等级 | 长边 | YDIF |'
        }

        It '有文字图存在异类页时应列出该页及其单图等级' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextMixed

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '### 与项目等级不一致的页面（1 张）'
            $Lines | Should -Contain '| cover_000.jpg | 有文字图 | Level 0 | 560px | 61.14 |'
        }

        It '仅无文字图存在异类页时类别应标为无文字图' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextMixed

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '| nt_009.jpg | 无文字图 | Level 2 | 900px | 1.4 |'
        }

        It '两类都有异类页时应合并为一张表且张数为合计' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextMixed -NonTextImageLevels $Script:NonTextMixed

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '### 与项目等级不一致的页面（2 张）'
            $Lines | Should -Contain '| cover_000.jpg | 有文字图 | Level 0 | 560px | 61.14 |'
            $Lines | Should -Contain '| nt_009.jpg | 无文字图 | Level 2 | 900px | 1.4 |'
        }

        It '只有无文字图时不应输出有文字图摘要行' {
            New-ReadmeFile @Script:BaseParams -NonTextImageLevels $Script:NonTextLevel1

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '- 无文字图: 1 张，长边 1920px，YDIF 8.75'
            @($Lines | Where-Object { $PSItem -like '- 有文字图: *' }).Count | Should -Be 1
            $Lines | Should -Contain '- 有文字图: 0 张'
        }
    }

    Context 'L5 输出字段验证' {
        BeforeEach {
            # 基线产物：Level 1、无项目简介、无异类页，行号稳定
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextLevel1 -NonTextImageLevels $Script:NonTextLevel1
            $Script:Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
        }

        It '首行应包含项目名与当日日期' {
            $Today = Get-Date -Format 'yyyy-MM-dd'

            $Script:Lines[0] | Should -BeExactly "# 项目记录: TestProject ($Today)"
            $Script:Lines[1] | Should -BeExactly ''
            $Script:Lines[2] | Should -BeExactly '## 项目基本信息'
        }

        It '项目基本信息六行应逐行精确' {
            $Script:Lines[3] | Should -BeExactly '- 有文字图: 2 张'
            $Script:Lines[4] | Should -BeExactly '- 无文字图: 1 张'
            $Script:Lines[5] | Should -BeExactly '- 合计: 3 张'
            $Script:Lines[6] | Should -BeExactly '- 项目统一等级: Level 1（FFmpeg 1.2 倍放大 + 锐化）'
            $Script:Lines[7] | Should -BeExactly '- 原始文件是否需要高清化: [X]'
            $Script:Lines[8] | Should -BeExactly '- 使用高清化倍数: 1.2'
        }

        It '预处理详情段的行序与摘要文本应精确' {
            $Script:Lines[10] | Should -BeExactly '## 预处理详情'
            $Script:Lines[11] | Should -BeExactly ''
            $Script:Lines[12] | Should -BeExactly '- 有文字图: 2 张，长边 2400–3000px，YDIF 2.5–3.5'
            $Script:Lines[13] | Should -BeExactly '- 无文字图: 1 张，长边 1920px，YDIF 8.75'
        }

        It '进度跟踪标题与六个复选项应逐行精确' {
            $Script:Lines[15] | Should -BeExactly '## 进度跟踪'
            $Script:Lines[16] | Should -BeExactly '- [ ] 文件整理与分离'
            $Script:Lines[17] | Should -BeExactly '- [ ] OCR 处理与校对'
            $Script:Lines[18] | Should -BeExactly '- [ ] Inpainting 处理与修正'
            $Script:Lines[19] | Should -BeExactly '- [ ] 文本翻译'
            $Script:Lines[20] | Should -BeExactly '- [ ] 嵌字 (完成至页 X)'
            $Script:Lines[21] | Should -BeExactly '- [ ] 最终质量检查'
        }

        It '文件末尾不应有多余空行' {
            $Script:Lines[-1] | Should -BeExactly '- [任何你想记下的其他信息]'
            ($Script:Lines[-1]).Length | Should -BeGreaterThan 0
        }

        It '异类页表头与分隔行应逐行精确' {
            New-ReadmeFile @Script:BaseParams -TextImageLevels $Script:TextMixed

            $Lines = @(Get-Content -LiteralPath $Script:ReadmePath)
            $Lines | Should -Contain '| 文件名 | 类别 | 单图等级 | 长边 | YDIF |'
            $Lines | Should -Contain '|--------|------|----------|------|------|'
        }
    }
}
