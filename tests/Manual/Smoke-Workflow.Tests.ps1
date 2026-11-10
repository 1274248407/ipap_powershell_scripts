#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 工作流真实工具链冒烟
.DESCRIPTION
    用合成图片驱动真实 ffmpeg / Real-CUGAN，验证三条路径：
    1. Start-IPAPWorkflow 全文字图 → FFmpeg 放大，产物落到 02_Preprocessing；
    2. Invoke-ParallelUpscale -Engine RealCugan → 直接验证 Real-CUGAN 与 GPU；
    3. Start-IPAPWorkflow 含无文字图 → 产物落到 02_Preprocessing\original_non_text_raw。

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

        $script:SrcAll = Join-Path $script:WorkRoot 'src-all'
        $script:SrcMixed = Join-Path $script:WorkRoot 'src-mixed'
        $script:RcSrc = Join-Path $script:WorkRoot 'rc-src'
        $script:BaseAll = Join-Path $script:WorkRoot 'base-all'
        $script:BaseMixed = Join-Path $script:WorkRoot 'base-mixed'
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

        # 合成图片：尺寸/格式差异用于覆盖格式探测与路径分支（当前 ffmpeg 构建下均为 Level 1）
        New-SyntheticImage -Path (Join-Path $script:SrcAll 'page1.png') -Size '2000x2800' -Filter 'noise=alls=80:allf=t+u'
        New-SyntheticImage -Path (Join-Path $script:SrcAll 'page2.jpg') -Size '1200x1700' -Filter 'drawgrid=w=40:h=40:t=2:c=black'
        New-SyntheticImage -Path (Join-Path $script:SrcAll 'page3.webp') -Size '900x1200' -Filter ''
        New-SyntheticImage -Path (Join-Path $script:RcSrc 'small.png') -Size '640x800' -Filter 'noise=alls=40:allf=t+u'
        New-SyntheticImage -Path (Join-Path $script:SrcMixed 'page1.png') -Size '1200x1700' -Filter 'drawgrid=w=40:h=40:t=2:c=black'
        New-SyntheticImage -Path (Join-Path $script:SrcMixed 'nontext\bg.png') -Size '1200x1600' -Filter 'drawbox=x=100:y=100:w=800:h=1000:c=green:t=fill'

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

$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $Repo 'source\IPAP.psd1') -Force

# 与 Main.ps1 的真实入口保持一致：不把 Real-CUGAN 写到 stderr 的进度行
# 当作终止错误（$ErrorActionPreference='Stop' 会让这些行中断并行块）

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

    Context '场景 1：全文字图 → FFmpeg' {
        BeforeAll {
            $script:Run1 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $script:BaseAll, '-SourceDir', $script:SrcAll
            ) -InputText "4`n"
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run1-workflow.log'), $script:Run1.Output, [Text.UTF8Encoding]::new($false))

            $script:Project1 = @(Get-ChildItem -LiteralPath $script:BaseAll -Directory -ErrorAction SilentlyContinue)
        }

        It '工作流退出码为 0' {
            $script:Run1.ExitCode | Should -Be 0
        }

        It '创建了一个项目目录' {
            $script:Project1.Count | Should -Be 1
        }

        It '02_Preprocessing 存在' {
            $script:Project1.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project1[0].FullName '02_Preprocessing') | Should -BeTrue
        }

        It '三张有文字图均产出 webp' {
            $script:Project1.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            $preprocessing = Join-Path $script:Project1[0].FullName '02_Preprocessing'
            @(Get-ChildItem -LiteralPath $preprocessing -File -Filter '*.webp' -ErrorAction SilentlyContinue).Count |
                Should -Be 3
        }

        It 'README.md 存在' {
            $script:Project1.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project1[0].FullName 'README.md') | Should -BeTrue
        }

        It '排版目录存在' {
            $script:Project1.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project1[0].FullName '03_Typesetting\final_pages') | Should -BeTrue
        }
    }

    Context '场景 2：Real-CUGAN 直接调用' {
        BeforeAll {
            $script:Run2 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'realcugan', '-Repo', $script:Repo, '-ImagePath', (Join-Path $script:RcSrc 'small.png'),
                '-OutputDir', $script:OutRc
            )
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run2-realcugan.log'), $script:Run2.Output, [Text.UTF8Encoding]::new($false))
        }

        It 'Real-CUGAN 退出码为 0' {
            $script:Run2.ExitCode | Should -Be 0
        }

        It 'Real-CUGAN 成功计数为 1' {
            $script:Run2.Output | Should -Match 'RESULT_SUCCESS=1'
        }

        It 'Real-CUGAN 产出 webp' {
            Test-Path -LiteralPath (Join-Path $script:OutRc 'small.webp') | Should -BeTrue
        }
    }

    Context '场景 3：含无文字图 → original_non_text_raw' {
        BeforeAll {
            # 选项菜单：子文件夹存在时为 [1] 起始编号 [2] 子文件夹 [3] 自定义路径 [4] 跳过
            $script:Run3 = Invoke-SmokeRunner -RunnerArguments @(
                '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $script:BaseMixed, '-SourceDir', $script:SrcMixed
            ) -InputText "2`n1`n"
            [IO.File]::WriteAllText((Join-Path $script:LogDir 'run3-nontext.log'), $script:Run3.Output, [Text.UTF8Encoding]::new($false))

            $script:Project3 = @(Get-ChildItem -LiteralPath $script:BaseMixed -Directory -ErrorAction SilentlyContinue)
        }

        It '工作流退出码为 0' {
            $script:Run3.ExitCode | Should -Be 0
        }

        It '创建了一个项目目录' {
            $script:Project3.Count | Should -Be 1
        }

        It '有文字图产物存在' {
            $script:Project3.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project3[0].FullName '02_Preprocessing\page1.webp') | Should -BeTrue
        }

        It '无文字图产物存在' {
            $script:Project3.Count | Should -Be 1 -Because '前置断言：项目目录应存在'
            Test-Path -LiteralPath (Join-Path $script:Project3[0].FullName '02_Preprocessing\original_non_text_raw\bg.webp') |
                Should -BeTrue
        }
    }
}
