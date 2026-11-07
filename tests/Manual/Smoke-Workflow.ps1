#Requires -Version 7.0

<#
.SYNOPSIS
    IPAP 工作流真实工具链冒烟（手动执行）
.DESCRIPTION
    用合成图片驱动真实 ffmpeg / Real-CUGAN，验证三条路径：
    1. Start-IPAPWorkflow 全文字图 → FFmpeg 放大，产物落到 02_Preprocessing；
    2. Invoke-ParallelUpscale -Engine RealCugan → 直接验证 Real-CUGAN 与 GPU；
    3. Start-IPAPWorkflow 含无文字图 → 产物落到 02_Preprocessing\original_non_text_raw。

    本脚本不匹配 *.Tests.ps1，不会被 Pester 自动收集；依赖本机 GPU 与 bin/ 下的真实工具。
    所有输入图片均由 ffmpeg 合成，不使用外部下载素材；工作目录默认保留以便检查产物与日志。
.PARAMETER WorkRoot
    工作目录，默认 %TEMP%\ipap-smoke。
.EXAMPLE
    pwsh -NoProfile -File .\tests\Manual\Smoke-Workflow.ps1
.INPUTS
    无
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
[CmdletBinding()]
[OutputType([void])]
param (
    [string]$WorkRoot = (Join-Path $env:TEMP 'ipap-smoke')
)

$ErrorActionPreference = 'Stop'

# tests\Manual → 仓库根
$script:Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:Failures = [System.Collections.Generic.List[string]]::new()

<#
.SYNOPSIS
    记录一条断言结果
.DESCRIPTION
    通过时输出绿色 PASS；失败时输出红色 FAIL 并累计，脚本末尾统一返回非零退出码。
.PARAMETER Condition
    断言条件。
.PARAMETER Name
    断言名称。
.OUTPUTS
    [void]
#>
function Assert-True {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Condition) {
        Write-Host ('[PASS] ' + $Name) -ForegroundColor Green
    }
    else {
        Write-Host ('[FAIL] ' + $Name) -ForegroundColor Red
        $script:Failures.Add($Name)
    }
}

<#
.SYNOPSIS
    在子进程中执行 runner 脚本
.DESCRIPTION
    子进程隔离模块状态；通过标准输入向 Start-IPAPWorkflow 内部的 Read-Host 提供选择。
.PARAMETER RunnerArguments
    传给 runner 的参数数组。
.PARAMETER InputText
    写入子进程标准输入的文本（空字符串表示不重定向）。
.OUTPUTS
    PSCustomObject（ExitCode / Output）
#>
function Invoke-Runner {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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

<#
.SYNOPSIS
    用 ffmpeg 生成合成图片
.DESCRIPTION
    输入为 lavfi 的 color 源，可选叠加滤镜；生成失败直接抛异常。
.PARAMETER Path
    输出文件路径。
.PARAMETER Size
    画布尺寸（如 2000x2800）。
.PARAMETER Filter
    可选的 -vf 滤镜链。
.OUTPUTS
    [void]
#>
function New-SyntheticImage {
    [CmdletBinding()]
    [OutputType([void])]
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

# 准备干净的工作目录
if (Test-Path -LiteralPath $WorkRoot) {
    Remove-Item -LiteralPath $WorkRoot -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $WorkRoot -Force
$LogDir = Join-Path $WorkRoot 'logs'
$null = New-Item -ItemType Directory -Path $LogDir -Force

$SrcAll = Join-Path $WorkRoot 'src-all'
$SrcMixed = Join-Path $WorkRoot 'src-mixed'
$RcSrc = Join-Path $WorkRoot 'rc-src'
$BaseAll = Join-Path $WorkRoot 'base-all'
$BaseMixed = Join-Path $WorkRoot 'base-mixed'
$OutRc = Join-Path $WorkRoot 'out-rc'

# 定位真实工具
$ffmpegItem = Get-ChildItem -Path (Join-Path $script:Repo 'bin') -Recurse -Filter 'ffmpeg.exe' -File |
    Select-Object -First 1
if (-not $ffmpegItem) {
    throw 'bin/ 下未找到 ffmpeg.exe'
}
$script:Ffmpeg = $ffmpegItem.FullName

# 合成图片：尺寸/格式差异用于覆盖格式探测与路径分支（当前 ffmpeg 构建下均为 Level 1）
New-SyntheticImage -Path (Join-Path $SrcAll 'page1.png') -Size '2000x2800' -Filter 'noise=alls=80:allf=t+u'
New-SyntheticImage -Path (Join-Path $SrcAll 'page2.jpg') -Size '1200x1700' -Filter 'drawgrid=w=40:h=40:t=2:c=black'
New-SyntheticImage -Path (Join-Path $SrcAll 'page3.webp') -Size '900x1200' -Filter ''
New-SyntheticImage -Path (Join-Path $RcSrc 'small.png') -Size '640x800' -Filter 'noise=alls=40:allf=t+u'
New-SyntheticImage -Path (Join-Path $SrcMixed 'page1.png') -Size '1200x1700' -Filter 'drawgrid=w=40:h=40:t=2:c=black'
New-SyntheticImage -Path (Join-Path $SrcMixed 'nontext\bg.png') -Size '1200x1600' -Filter 'drawbox=x=100:y=100:w=800:h=1000:c=green:t=fill'

# 子进程 runner：隔离模块状态，并由标准输入驱动交互选择
$script:Runner = Join-Path $WorkRoot 'runner.ps1'
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

# === 场景 1：全文字图，FFmpeg 路径 ===
$Run1 = Invoke-Runner -RunnerArguments @(
    '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $BaseAll, '-SourceDir', $SrcAll
) -InputText "4`n"
[IO.File]::WriteAllText((Join-Path $LogDir 'run1-workflow.log'), $Run1.Output, [Text.UTF8Encoding]::new($false))

Assert-True -Condition ($Run1.ExitCode -eq 0) -Name 'run1 工作流退出码为 0'
$Project1 = @(Get-ChildItem -LiteralPath $BaseAll -Directory -ErrorAction SilentlyContinue | Select-Object -First 1)
Assert-True -Condition ($Project1.Count -eq 1) -Name 'run1 创建了一个项目目录'
if ($Project1.Count -eq 1) {
    $Pre1 = Join-Path $Project1[0].FullName '02_Preprocessing'
    Assert-True -Condition (Test-Path -LiteralPath $Pre1) -Name 'run1 02_Preprocessing 存在'
    $Upscaled1 = @(Get-ChildItem -LiteralPath $Pre1 -File -Filter '*.webp' -ErrorAction SilentlyContinue)
    Assert-True -Condition ($Upscaled1.Count -eq 3) -Name 'run1 三张有文字图均产出 webp'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $Project1[0].FullName 'README.md')) -Name 'run1 README.md 存在'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $Project1[0].FullName '03_Typesetting\final_pages')) -Name 'run1 排版目录存在'
}

# === 场景 2：Real-CUGAN 直接调用 ===
$Run2 = Invoke-Runner -RunnerArguments @(
    '-Mode', 'realcugan', '-Repo', $script:Repo, '-ImagePath', (Join-Path $RcSrc 'small.png'), '-OutputDir', $OutRc
)
[IO.File]::WriteAllText((Join-Path $LogDir 'run2-realcugan.log'), $Run2.Output, [Text.UTF8Encoding]::new($false))

Assert-True -Condition ($Run2.ExitCode -eq 0) -Name 'run2 Real-CUGAN 退出码为 0'
Assert-True -Condition ($Run2.Output -match 'RESULT_SUCCESS=1') -Name 'run2 Real-CUGAN 成功计数为 1'
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $OutRc 'small.webp')) -Name 'run2 Real-CUGAN 产出 webp'

# === 场景 3：含无文字图，走 original_non_text_raw ===
# 选项菜单：子文件夹存在时为 [1] 起始编号 [2] 子文件夹 [3] 自定义路径 [4] 跳过
$Run3 = Invoke-Runner -RunnerArguments @(
    '-Mode', 'workflow', '-Repo', $script:Repo, '-BaseDir', $BaseMixed, '-SourceDir', $SrcMixed
) -InputText "2`n1`n"
[IO.File]::WriteAllText((Join-Path $LogDir 'run3-nontext.log'), $Run3.Output, [Text.UTF8Encoding]::new($false))

Assert-True -Condition ($Run3.ExitCode -eq 0) -Name 'run3 工作流退出码为 0'
$Project3 = @(Get-ChildItem -LiteralPath $BaseMixed -Directory -ErrorAction SilentlyContinue | Select-Object -First 1)
Assert-True -Condition ($Project3.Count -eq 1) -Name 'run3 创建了一个项目目录'
if ($Project3.Count -eq 1) {
    $Pre3 = Join-Path $Project3[0].FullName '02_Preprocessing'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $Pre3 'page1.webp')) -Name 'run3 有文字图产物存在'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $Pre3 'original_non_text_raw\bg.webp')) -Name 'run3 无文字图产物存在'
}

# === 汇总 ===
Write-Host ''
if ($script:Failures.Count -eq 0) {
    Write-Host '冒烟通过：FFmpeg、Real-CUGAN、无文字图三条路径均正常' -ForegroundColor Green
}
else {
    Write-Host ('冒烟失败 {0} 项：' -f $script:Failures.Count) -ForegroundColor Red
    foreach ($failure in $script:Failures) {
        Write-Host ('  - ' + $failure) -ForegroundColor Red
    }
    Write-Host ('工作目录保留在：' + $WorkRoot)
    exit 1
}

Write-Host ('工作目录保留在：' + $WorkRoot)
