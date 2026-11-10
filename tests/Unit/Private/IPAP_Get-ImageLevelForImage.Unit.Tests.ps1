#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ImageLevelForImage 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖单图分级：
    L1 正常分级、L2 外部进程失败/异常、L3 阈值边界、
    L4 分支与临时目录清理、L5 五字段验证。
    外部进程通过 -InvokeFfprobe / -InvokeFfmpeg 注入假实现，
    不依赖真实 ffmpeg，也不写入真实项目目录。
#>

Describe 'Get-ImageLevelForImage Unit Tests' -Tag 'Get-ImageLevelForImage', 'IPAP' {
    BeforeAll {
        # tests\Unit\Private → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 统一构造假的外部进程适配器并调用 worker
        function Invoke-LevelWorker {
            [CmdletBinding()]
            param(
                [object]$Image,
                [string]$ProbeOutput = '1920x1080',
                [int]$ProbeExit = 0,
                [int]$FfmpegBytes = 6144,
                [int]$FfmpegExit = 0,
                [double]$HighDetailThreshold = 6.0,
                [double]$MediumDetailThreshold = 3.0,
                [switch]$ProbeThrows,
                [switch]$FfmpegThrows
            )
            InModuleScope IPAP -Parameters @{
                TargetImage    = $Image
                Output         = $ProbeOutput
                ProbeCode      = $ProbeExit
                Bytes          = $FfmpegBytes
                FfmpegCode     = $FfmpegExit
                HighThreshold  = $HighDetailThreshold
                MediumThreshold = $MediumDetailThreshold
                ThrowProbe     = [bool]$ProbeThrows
                ThrowFfmpeg    = [bool]$FfmpegThrows
            } -ScriptBlock {
                param($TargetImage, $Output, $ProbeCode, $Bytes, $FfmpegCode, $HighThreshold, $MediumThreshold, $ThrowProbe, $ThrowFfmpeg)

                # 使用模块作用域变量，避免脚本块动态作用域丢失局部参数
                $script:ProbeOutputValue = $Output
                $script:ProbeExitValue = $ProbeCode
                $script:ProbeShouldThrow = $ThrowProbe
                $script:FfmpegBytesValue = $Bytes
                $script:FfmpegExitValue = $FfmpegCode
                $script:FfmpegShouldThrow = $ThrowFfmpeg

                $probe = {
                    param($Path, $Arguments)
                    if ($script:ProbeShouldThrow) { throw 'ffprobe failed' }
                    return [PSCustomObject]@{ Output = $script:ProbeOutputValue; ExitCode = $script:ProbeExitValue }
                }
                $ffmpeg = {
                    param($Path, $Arguments)
                    if ($script:FfmpegShouldThrow) { throw 'ffmpeg failed' }
                    if ($script:FfmpegExitValue -eq 0 -and $script:FfmpegBytesValue -ge 0) {
                        [IO.File]::WriteAllBytes($Arguments[-1], [byte[]]::new($script:FfmpegBytesValue))
                    }
                    return [PSCustomObject]@{ Output = ''; ExitCode = $script:FfmpegExitValue }
                }

                return Get-ImageLevelForImage -Index 0 -Image $TargetImage `
                    -FfprobePath 'fake-ffprobe' -FfmpegPath 'fake-ffmpeg' `
                    -HighDetailThreshold $HighThreshold -MediumDetailThreshold $MediumThreshold `
                    -InvokeFfprobe $probe -InvokeFfmpeg $ffmpeg
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 共享基础数据：单张图片对象
        $script:Image = [PSCustomObject]@{ FullName = 'D:\images\sample.png' }
    }

    Context 'L1 正常分级' {
        It '1920x1080 且 YDIF 为 6 时应为 Level 0' {
            $result = Invoke-LevelWorker -Image $script:Image

            $result | Should -BeOfType [PSCustomObject]
            $result.Index | Should -Be 0
            $result.Image | Should -Be $script:Image
            $result.Level | Should -Be 0
            $result.LongEdge | Should -Be 1920
            $result.YDIF | Should -Be 6.0
            $result.DetailError | Should -Be ''
        }

        It '800x600 且 YDIF 为 2.5 时应为 Level 2' {
            $result = Invoke-LevelWorker -Image $script:Image -ProbeOutput '800x600' -FfmpegBytes 2560

            $result.Level | Should -Be 2
            $result.LongEdge | Should -Be 800
            $result.YDIF | Should -Be 2.5
        }
    }

    Context 'L2 外部进程失败与异常' {
        It 'ffprobe 非零退出时应回退到 Level 1 与 YDIF 5.0' {
            $result = Invoke-LevelWorker -Image $script:Image -ProbeExit 1

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 0
            $result.YDIF | Should -Be 5.0
            $result.DetailError | Should -Be 'FFprobe 未能解析出分辨率'
        }

        It 'ffprobe 输出不匹配时应回退到 Level 1 与 YDIF 5.0' {
            $result = Invoke-LevelWorker -Image $script:Image -ProbeOutput 'invalid-output'

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 0
            $result.YDIF | Should -Be 5.0
        }

        It 'ffmpeg 非零退出时应保留长边并使用 YDIF 5.0' {
            $result = Invoke-LevelWorker -Image $script:Image -FfmpegExit 1

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 1920
            $result.YDIF | Should -Be 5.0
            $result.DetailError | Should -Be 'edgedetect 输出缺失或 FFmpeg 退出码非 0'
        }

        It 'ffmpeg 成功但未生成输出文件时应使用 YDIF 5.0' {
            $result = Invoke-LevelWorker -Image $script:Image -FfmpegBytes -1

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 1920
            $result.YDIF | Should -Be 5.0
        }

        It 'ffprobe 调用抛异常时应回退到 Level 1 与 YDIF 5.0' {
            $result = Invoke-LevelWorker -Image $script:Image -ProbeThrows

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 0
            $result.YDIF | Should -Be 5.0
        }

        It 'ffmpeg 调用抛异常时应保留长边并使用 YDIF 5.0' {
            $result = Invoke-LevelWorker -Image $script:Image -FfmpegThrows

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 1920
            $result.YDIF | Should -Be 5.0
        }
    }

    Context 'L3 阈值边界' {
        It '长边 1100 且 YDIF 0 时应为 Level 1' {
            $result = Invoke-LevelWorker -Image $script:Image -ProbeOutput '1100x800' -FfmpegBytes 0

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 1100
            $result.YDIF | Should -Be 0
        }

        It '长边 1099 且 YDIF 3.0 时应为 Level 1' {
            $result = Invoke-LevelWorker -Image $script:Image -ProbeOutput '1099x800' -FfmpegBytes 3072

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 1099
            $result.YDIF | Should -Be 3.0
        }

        It '长边 1099 且 YDIF 2.99 时应为 Level 2' {
            $result = Invoke-LevelWorker -Image $script:Image -ProbeOutput '1099x800' -FfmpegBytes 3060

            $result.Level | Should -Be 2
            $result.LongEdge | Should -Be 1099
            $result.YDIF | Should -Be 2.99
        }

        It '长边 1920 且 YDIF 5.99 时应为 Level 1' {
            $result = Invoke-LevelWorker -Image $script:Image -FfmpegBytes 6133

            $result.Level | Should -Be 1
            $result.LongEdge | Should -Be 1920
            $result.YDIF | Should -Be 5.99
        }

        It '高细节阈值可配置：阈值 100 时 1920 宽、YDIF 6.0 应降为 Level 1' {
            $result = Invoke-LevelWorker -Image $script:Image -HighDetailThreshold 100

            $result.Level | Should -Be 1
            $result.YDIF | Should -Be 6.0
        }

        It '中细节阈值可配置：阈值 0 时 800 宽、YDIF 2.5 应升为 Level 1' {
            $result = Invoke-LevelWorker -Image $script:Image -ProbeOutput '800x600' -FfmpegBytes 2560 `
                -MediumDetailThreshold 0

            $result.Level | Should -Be 1
            $result.YDIF | Should -Be 2.5
        }
    }

    Context 'L4 分支与副作用清理' {
        It '成功路径后临时目录应被清理' {
            [string]$originalTemp = $env:TEMP
            [string]$tempRoot = Join-Path $TestDrive 'WorkerTempSuccess'
            New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
            $env:TEMP = $tempRoot
            try {
                $null = Invoke-LevelWorker -Image $script:Image
            }
            finally {
                $env:TEMP = $originalTemp
            }

            @(Get-ChildItem -LiteralPath $tempRoot -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It '失败路径后临时目录应被清理' {
            [string]$originalTemp = $env:TEMP
            [string]$tempRoot = Join-Path $TestDrive 'WorkerTempFailure'
            New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
            $env:TEMP = $tempRoot
            try {
                $null = Invoke-LevelWorker -Image $script:Image -FfmpegExit 1
            }
            finally {
                $env:TEMP = $originalTemp
            }

            @(Get-ChildItem -LiteralPath $tempRoot -Directory -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It '未注入适配器时应调用真实可执行文件并完成分级' {
            # 默认适配器路径：用真实的 .cmd 模拟 ffprobe/ffmpeg，覆盖 & 调用与 LASTEXITCODE 分支
            [string]$probePath = Join-Path $TestDrive 'fake-ffprobe.cmd'
            [string]$ffmpegPath = Join-Path $TestDrive 'fake-ffmpeg.cmd'
            Set-Content -LiteralPath $probePath -Value "@echo off`r`necho 1920x1080`r`nexit /b 0" -Encoding ascii
            Set-Content -LiteralPath $ffmpegPath -Value @'
@echo off
setlocal
:loop
if "%~1"=="" goto done
set "LAST=%~1"
shift
goto loop
:done
fsutil file createnew "%LAST%" 6144 >nul
exit /b 0
'@ -Encoding ascii

            $result = InModuleScope IPAP -Parameters @{
                ProbePath  = $probePath
                FfmpegPath = $ffmpegPath
                TargetImage = $script:Image
            } -ScriptBlock {
                param($ProbePath, $FfmpegPath, $TargetImage)
                Get-ImageLevelForImage -Index 0 -Image $TargetImage -FfprobePath $ProbePath -FfmpegPath $FfmpegPath
            }

            $result.Level | Should -Be 0
            $result.LongEdge | Should -Be 1920
            $result.YDIF | Should -Be 6.0
        }
    }

    Context 'L5 输出字段' {
        It '结果对象应恰好包含 Index / Image / Level / LongEdge / YDIF / DetailError 六个字段' {
            $result = Invoke-LevelWorker -Image $script:Image

            @($result.PSObject.Properties.Name | Sort-Object) |
                Should -Be @('DetailError', 'Image', 'Index', 'Level', 'LongEdge', 'YDIF')
            ($result.Index -is [int]) | Should -BeTrue
            ($result.Level -is [int]) | Should -BeTrue
            ($result.LongEdge -is [int]) | Should -BeTrue
            ($result.YDIF -is [double]) | Should -BeTrue
            $result.DetailError | Should -BeOfType [string]
        }
    }
}
