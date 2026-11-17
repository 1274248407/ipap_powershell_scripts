#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 工作流真实工具链冒烟
.DESCRIPTION
    用合成图片驱动真实 ffmpeg / Real-CUGAN，验证项目统一等级的四条路径：
    1. 全部 Level 0 → 不放大，但三张全部转码为 webp；
    2. 全部 Level 1 → 三张都走 FFmpeg 放大，落到 02_Preprocessing；
    3. 有文字图 + 无文字图且同等级 → 分别落到 02_Preprocessing 与 original_non_text_raw；
    4. 全部 Level 2 → 项目整批走 Real-CUGAN；
    5. 含损坏图片 → 转码失败兜底复制原图、校验失败、退出码非零；
    另有 Real-CUGAN 直接调用，单独验证推理链路与 GPU 可用性。

    同一项目内所有页面必须同一等级（见 GLOSSARY「统一等级」），
    因此每个场景的输入目录只放一种等级的合成图，不再混级。

    本文件位于 tests/Manual，会被 build.ps1 -Task Test 收集；也可用 -Task Smoke 单独运行。
    工作目录默认 %TEMP%\ipap-smoke，可用环境变量 IPAP_SMOKE_ROOT 覆盖；每次运行前清空，
    结束后保留现场以便查看日志与产物。所有输入图片由 ffmpeg 合成，不使用外部素材。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'IPAP Workflow Smoke' -Tag 'Smoke', 'IPAP' {
    BeforeAll {
        # tests\Manual → 仓库根
        $script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:WorkRoot = if ($env:IPAP_SMOKE_ROOT) {
            $env:IPAP_SMOKE_ROOT
        }
        else {
            Join-Path $env:TEMP 'ipap-smoke'
        }

        # 每次运行前清空工作目录；结束后保留现场
        if (Test-Path -LiteralPath $script:WorkRoot) {
            Remove-Item -LiteralPath $script:WorkRoot -Recurse -Force
        }
        $null = New-Item -ItemType Directory -Path $script:WorkRoot -Force
        $script:LogDir = Join-Path $script:WorkRoot 'logs'
        $null = New-Item -ItemType Directory -Path $script:LogDir -Force

        $script:SrcL0 = Join-Path $script:WorkRoot 'src-l0'
        $script:SrcL1 = Join-Path $script:WorkRoot 'src-l1'
        $script:SrcL2 = Join-Path $script:WorkRoot 'src-l2'
        $script:SrcMixed = Join-Path $script:WorkRoot 'src-mixed'
        $script:SrcBroken = Join-Path $script:WorkRoot 'src-broken'
        $script:BaseL0 = Join-Path $script:WorkRoot 'base-l0'
        $script:BaseL1 = Join-Path $script:WorkRoot 'base-l1'
        $script:BaseL2 = Join-Path $script:WorkRoot 'base-l2'
        $script:BaseMixed = Join-Path $script:WorkRoot 'base-mixed'
        $script:BaseBroken = Join-Path $script:WorkRoot 'base-broken'
        $script:OutRc = Join-Path $script:WorkRoot 'out-rc'

        # 定位真实工具
        $ffmpegItem = Get-ChildItem -Path (Join-Path $script:Repo 'bin') -Recurse -Filter 'ffmpeg.exe' -File |
            Select-Object -First 1
        $ffmpegItem | Should -Not -BeNullOrEmpty -Because 'bin/ 下应存在 ffmpeg.exe'
        $script:Ffmpeg = $ffmpegItem.FullName

        function New-SyntheticImage {
            param (
                [Parameter(Mandatory = $true)]
                [string]$Path,
                [Parameter(Mandatory = $true)]
                [string]$Size,
                [string]$Filter
            )

            $parent = Split-Path -Parent $Path
            if (-not (Test-Path -LiteralPath $parent)) {
                $null = New-Item -ItemType Directory -Path $parent -Force
            }

            $arguments = @('-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', "color=c=white:s=$Size")
            if ($Filter) {
                $arguments += @('-vf', $Filter)
            }
            $arguments += @('-frames:v', '1', '-y', $Path)

            & $script:Ffmpeg @arguments | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path)) {
                throw "生成合成图片失败: $Path"
            }
        }

        function Invoke-SmokeRunner {
            param (
                [Parameter(Mandatory = $true)]
                [string[]]$RunnerArguments,
                [string]$InputText = ''
            )

            if ($InputText) {
                $raw = $InputText | & pwsh -NoProfile -File $script:Runner @RunnerArguments 2>&1 | Out-String
            }
            else {
                $raw = & pwsh -NoProfile -File $script:Runner @RunnerArguments 2>&1 | Out-String
            }

            return [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output   = $raw
            }
        }

        # Level 0：长边 2800 且噪声密集，边缘图很大 → 高细节
        New-SyntheticImage -Path (Join-Path $script:SrcL0 'page1.png') -Size '2000x2800' -Filter 'noise=alls=80:allf=t+u'
        New-SyntheticImage -Path (Join-Path $script:SrcL0 'page2.jpg') -Size '2000x2800' -Filter 'noise=alls=80:allf=t+u'
        New-SyntheticImage -Path (Join-Path $script:SrcL0 'page3.webp') -Size '2000x2800' -Filter 'noise=alls=80:allf=t+u'

        # Level 1：长边 1700（>= 1100），细节中等
        New-SyntheticImage -Path (Join-Path $script:SrcL1 'page1.png') -Size '1200x1700' -Filter 'drawgrid=w=40:h=40:t=2:c=black'
        New-SyntheticImage -Path (Join-Path $script:SrcL1 'page2.jpg') -Size '1200x1700' -Filter 'drawgrid=w=40:h=40:t=2:c=black'
        New-SyntheticImage -Path (Join-Path $script:SrcL1 'page3.webp') -Size '1200x1700' -Filter 'drawgrid=w=40:h=40:t=2:c=black'

        # Level 2：长边 1000（< 1100）且接近空白，细节不足
        New-SyntheticImage -Path (Join-Path $script:SrcL2 'page1.png') -Size '800x1000' -Filter ''
        New-SyntheticImage -Path (Join-Path $script:SrcL2 'page2.jpg') -Size '800x1000' -Filter ''

        # 有文字图 1 张 + 无文字图 1 张，两者单图等级都是 Level 1
        New-SyntheticImage -Path (Join-Path $script:SrcMixed 'page1.png') -Size '1200x1700' -Filter 'drawgrid=w=40:h=40:t=2:c=black'
        New-SyntheticImage -Path (Join-Path $script:SrcMixed 'nontext\bg.png') -Size '1200x1600' -Filter 'drawbox=x=100:y=100:w=800:h=1000:c=green:t=fill'

        # 故意损坏的图片：扩展名合法但内容不是图片，用于验证「转码失败 → 兜底复制 → 校验失败 → 退出码非零」
        New-SyntheticImage -Path (Join-Path $script:SrcBroken 'page1.png') -Size '2000x2800' -Filter 'noise=alls=80:allf=t+u'
        New-SyntheticImage -Path (Join-Path $script:SrcBroken 'page2.png') -Size '2000x2800' -Filter 'noise=alls=80:allf=t+u'
        $null = New-Item -ItemType Directory -Path $script:SrcBroken -Force
        [IO.File]::WriteAllText((Join-Path $script:SrcBroken 'broken.jpg'), 'this is not an image')

        # 子进程 runner：隔离模块状态，并由标准输入驱动交互选择
        $script:Runner = Join-Path $script:WorkRoot 'runner.ps1'
        [IO.File]::WriteAllText($script:Runner, @'
param (
    [ValidateSet('workflow', 'realcugan')]
    [string]$Mode,
    [string]$Repo,
    [string]$BaseDir,
    [string]$SourceDir,
    [string]$ImagePath,
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'source\IPAP.psd1') -Force

# 模块默认适配器已重定向并丢弃 stderr；这里用 Stop 验证 Real-CUGAN 的
# GPU 进度行不会再把并行块当作终止错误

# 工作目录指向仓库根，读取仓库根目录的 config.toml
$Config = Get-Configuration -ProjectRoot $Repo

if ($Mode -eq 'workflow') {
    Start-IPAPWorkflow -Config $Config -BaseDir $BaseDir -SourceDir $SourceDir
}
else {
    $Image = [PSCustomObject]@{
        FullName = $ImagePath
        Name     = (Split-Path -Path $ImagePath -Leaf)
    }
    $Result = Invoke-ParallelUpscale -Images @($Image) -OutputDir $OutputDir `
        -Engine 'RealCugan' -MaxWorkers 1 -Scale 2 -NoiseLevel 0 -ModelPath 'models-se' -OutputFormat 'webp'
    if ($Result.FailedCount -gt 0) {
        throw ("Real-CUGAN 失败计数: {0}" -f $Result.FailedCount)
    }
    Write-Output ("RESULT_SUCCESS={0}" -f $Result.SuccessCount)
}
'@, [Text.UTF8Encoding]::new($false))
    }

    Context '场景 1：全 Level 0 项目 → 转码不放大' {
        BeforeAll {
            # 无子文件夹时选项为 [1] 起始编号 [2] 自定义路径 [3] 跳过
            $script:Run1 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $script:BaseL0, '-SourceDir', $script:SrcL0
            ) -InputText "3`n"
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run1-level0.log'), $script:Run1.Output, [Text.UTF8Encoding]::new($false))

            $script:Project1 = @(Get-ChildItem -LiteralPath $script:BaseL0 -Directory -ErrorAction SilentlyContinue)
        }

        It '工作流退出码为 0' {
            $script:Run1.ExitCode | Should -Be 0
        }

        It '创建了一个项目目录' {
            $script:Project1.Count | Should -Be 1
        }

        It '项目统一等级应为 Level 0' {
            $script:Run1.Output | Should -Match '项目统一等级: Level 0'
        }

        It '三张图应全部转码为 webp' {
            $script:Project1.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            $preprocessing = Join-Path $script:Project1[0].FullName '02_Preprocessing'
            @(Get-ChildItem -LiteralPath $preprocessing -File -Filter '*.webp' -ErrorAction SilentlyContinue).Count |
                Should -Be 3
        }

        It '根目录不应残留非 webp 的图片文件' {
            $script:Project1.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            $preprocessing = Join-Path $script:Project1[0].FullName '02_Preprocessing'
            @(Get-ChildItem -LiteralPath $preprocessing -File |
                    Where-Object { $PSItem.Extension -in @('.jpg', '.jpeg', '.png') }).Count |
                Should -Be 0
        }

        It '日志应显示转码而不是放大' {
            $script:Run1.Output | Should -Match '有文字图: 转码 3 张为 webp'
            $script:Run1.Output | Should -Not -Match 'FFmpeg 锐化'
        }

        It 'raw_source 应保留三张原图' {
            $script:Project1.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            @(Get-ChildItem -LiteralPath (Join-Path $script:Project1[0].FullName '02_Preprocessing\raw_source') -File -ErrorAction SilentlyContinue).Count |
                Should -Be 3
        }

        It 'README.md 存在并记录项目等级与张数' {
            $script:Project1.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            $readme = Join-Path $script:Project1[0].FullName 'README.md'
            Test-Path -LiteralPath $readme | Should -BeTrue

            $lines = Get-Content -LiteralPath $readme -Encoding UTF8
            $lines | Should -Contain '- 有文字图: 3 张'
            $lines | Should -Contain '- 无文字图: 0 张'
            $lines | Should -Contain '- 合计: 3 张'
            $lines | Should -Contain '- 项目统一等级: Level 0（已高清，不放大）'
            $lines | Should -Contain '- 原始文件是否需要高清化: [ ]'
        }
    }

    Context '场景 2：全 Level 1 项目 → 整批 FFmpeg 放大' {
        BeforeAll {
            $script:Run2 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $script:BaseL1, '-SourceDir', $script:SrcL1
            ) -InputText "3`n"
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run2-level1.log'), $script:Run2.Output, [Text.UTF8Encoding]::new($false))

            $script:Project2 = @(Get-ChildItem -LiteralPath $script:BaseL1 -Directory -ErrorAction SilentlyContinue)
        }

        It '工作流退出码为 0' {
            $script:Run2.ExitCode | Should -Be 0
        }

        It '项目统一等级应为 Level 1' {
            $script:Run2.Output | Should -Match '项目统一等级: Level 1'
        }

        It '三张图应全部产出 webp' {
            $script:Project2.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            $preprocessing = Join-Path $script:Project2[0].FullName '02_Preprocessing'
            @(Get-ChildItem -LiteralPath $preprocessing -File -Filter '*.webp' -ErrorAction SilentlyContinue).Count |
                Should -Be 3
        }

        It 'raw_source 应保留三张原图' {
            $script:Project2.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            @(Get-ChildItem -LiteralPath (Join-Path $script:Project2[0].FullName '02_Preprocessing\raw_source') -File -ErrorAction SilentlyContinue).Count |
                Should -Be 3
        }
    }

    Context '场景 3：Real-CUGAN 直接调用' {
        BeforeAll {
            $script:Run3 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'realcugan', '-Repo', $script:Repo, '-ImagePath', (Join-Path $script:SrcL2 'page1.png'),
                '-OutputDir', $script:OutRc
            )
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run3-realcugan.log'), $script:Run3.Output, [Text.UTF8Encoding]::new($false))
        }

        It 'Real-CUGAN 退出码为 0' {
            $script:Run3.ExitCode | Should -Be 0
        }

        It 'Real-CUGAN 成功计数为 1' {
            $script:Run3.Output | Should -Match 'RESULT_SUCCESS=1'
        }

        It 'Real-CUGAN 产出 webp' {
            Test-Path -LiteralPath (Join-Path $script:OutRc 'page1.webp') | Should -BeTrue
        }
    }

    Context '场景 4：有文字图 + 无文字图，同等级 Level 1' {
        BeforeAll {
            # 有子文件夹时选项为 [1] 起始编号 [2] 子文件夹 [3] 自定义路径 [4] 跳过
            $script:Run4 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $script:BaseMixed, '-SourceDir', $script:SrcMixed
            ) -InputText "2`n1`n"
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run4-mixed.log'), $script:Run4.Output, [Text.UTF8Encoding]::new($false))

            $script:Project4 = @(Get-ChildItem -LiteralPath $script:BaseMixed -Directory -ErrorAction SilentlyContinue)
        }

        It '工作流退出码为 0' {
            $script:Run4.ExitCode | Should -Be 0
        }

        It '项目统一等级应为 Level 1' {
            $script:Run4.Output | Should -Match '项目统一等级: Level 1'
        }

        It '有文字图产物存在' {
            $script:Project4.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project4[0].FullName '02_Preprocessing\page1.webp') | Should -BeTrue
        }

        It '无文字图产物存在' {
            $script:Project4.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project4[0].FullName '02_Preprocessing\original_non_text_raw\bg.webp') |
                Should -BeTrue
        }

        It 'README 应记录两类张数合计' {
            $script:Project4.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            $lines = Get-Content -LiteralPath (Join-Path $script:Project4[0].FullName 'README.md') -Encoding UTF8
            $lines | Should -Contain '- 有文字图: 1 张'
            $lines | Should -Contain '- 无文字图: 1 张'
            $lines | Should -Contain '- 合计: 2 张'
            $lines | Should -Contain '- 项目统一等级: Level 1（FFmpeg 1.2 倍放大 + 锐化）'
        }
    }

    Context '场景 5：全 Level 2 项目 → 整批 Real-CUGAN' {
        BeforeAll {
            $script:Run5 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $script:BaseL2, '-SourceDir', $script:SrcL2
            ) -InputText "3`n"
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run5-level2.log'), $script:Run5.Output, [Text.UTF8Encoding]::new($false))

            $script:Project5 = @(Get-ChildItem -LiteralPath $script:BaseL2 -Directory -ErrorAction SilentlyContinue)
        }

        It '工作流退出码为 0' {
            $script:Run5.ExitCode | Should -Be 0
        }

        It '项目统一等级应为 Level 2' {
            $script:Run5.Output | Should -Match '项目统一等级: Level 2'
        }

        It '两张图应全部产出 webp' {
            $script:Project5.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            $preprocessing = Join-Path $script:Project5[0].FullName '02_Preprocessing'
            @(Get-ChildItem -LiteralPath $preprocessing -File -Filter '*.webp' -ErrorAction SilentlyContinue).Count |
                Should -Be 2
        }
    }

    Context '场景 6：转码失败 → 兜底复制原图 → 校验失败 → 退出码非零' {
        BeforeAll {
            $script:Run6 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $script:BaseBroken, '-SourceDir', $script:SrcBroken
            ) -InputText "3`n"
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run6-broken.log'), $script:Run6.Output, [Text.UTF8Encoding]::new($false))

            $script:Project6 = @(Get-ChildItem -LiteralPath $script:BaseBroken -Directory -ErrorAction SilentlyContinue)
        }

        It '工作流退出码应为非零' {
            $script:Run6.ExitCode | Should -Not -Be 0
        }

        It '损坏图片应记录处理失败警告' {
            $script:Run6.Output | Should -Match '图片处理失败: broken\.jpg'
        }

        It '校验未通过应记录 Error 并给出结论' {
            $script:Run6.Output | Should -Match '预处理输出校验未通过'
        }

        It '失败页应兜底复制为原扩展名而不是整页丢失' {
            $script:Project6.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project6[0].FullName '02_Preprocessing\broken.jpg') | Should -BeTrue
        }

        It '其余页面仍应正常产出 webp（单张失败不中断批次）' {
            $script:Project6.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project6[0].FullName '02_Preprocessing\page1.webp') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:Project6[0].FullName '02_Preprocessing\page2.webp') | Should -BeTrue
        }
    }
}
