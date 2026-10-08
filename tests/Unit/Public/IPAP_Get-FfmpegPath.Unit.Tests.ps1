#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-FfmpegPath 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五级要求覆盖 Get-FfmpegPath 的两条分支：
    L1 正常流程      —— Context 'L1 正常流程'
    L2 异常流程      —— Context 'L2 异常流程'
    L3 边界数据      —— 并入 L1（空字符串与 $null 同为"未配置"）

    设计要点：
    - Write-LogEntry 不设 Mock，走真实实现，用以钉住"日志已发出且 Write-LogEntry
      本身不抛异常"这一前提；终止错误由源码第 34 行的
      throw [System.IO.FileNotFoundException] 抛出。
    - Write-Host 为模块外部依赖，Mock 后捕获 5 段输出，既隔离终端副作用
      又可断言 ERROR 段确实在异常之前写出。
    - Get-Configuration 为模块内命令，Mock 须带 -ModuleName IPAP。
.INPUTS
    无
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
#>

Describe 'Get-FfmpegPath Unit Tests' -Tag 'Get-FfmpegPath', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # Mock Write-Host 记录每段调用参数，供"日志先于异常写出"断言使用
        $script:WriteHostCalls = @()
        Mock -CommandName Write-Host -ModuleName IPAP {
            param($Object, $NoNewline, $ForegroundColor, $BackgroundColor)
            $script:WriteHostCalls += [pscustomobject]@{
                Text            = [string]::Join('', @($Object))
                NoNewline       = $NoNewline
                ForegroundColor = [string]$ForegroundColor
                BackgroundColor = [string]$BackgroundColor
            }
        }
    }

    Context 'L1 正常流程' {
        It '配置给出 FfmpegExePath 时返回该路径且不写日志' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ FfmpegExePath = 'C:\tools\ffmpeg\ffmpeg.exe' }
                }
            }

            $Result = Get-FfmpegPath

            $Result | Should -Be 'C:\tools\ffmpeg\ffmpeg.exe'
            $script:WriteHostCalls.Count | Should -Be 0 -Because '命中配置时不应产生任何日志输出'
        }
    }

    Context 'L2 异常流程' {
        It '配置未给出 FfmpegExePath 时抛出 FileNotFoundException 并先记录 ERROR 日志' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ FfmpegExePath = '' }
                }
            }

            $ScriptBlock = { Get-FfmpegPath }

            # 终止错误须由源码显式 throw 的强类型异常抛出，而非 Write-LogEntry 的裸字符串
            $ScriptBlock | Should -Throw -ExceptionType ([System.IO.FileNotFoundException]) -ExpectedMessage '未找到 FFmpeg'

            # Write-LogEntry 为纯日志函数：ERROR 段在异常之前已完整写出，且只写 5 段、不额外中断
            $script:WriteHostCalls.Count | Should -Be 5 -Because '应恰输出一条完整日志行'
            $script:WriteHostCalls[1].Text | Should -Be '| ERROR   | '
            $script:WriteHostCalls[3].Text | Should -Be '未找到 FFmpeg'
            $script:WriteHostCalls[3].BackgroundColor | Should -Be 'Red'
        }

        It '配置未给出 FfmpegExePath（$null）时同样抛出 FileNotFoundException' {
            Mock -CommandName Get-Configuration -ModuleName IPAP {
                [pscustomobject]@{
                    Tools = [pscustomobject]@{ FfmpegExePath = $null }
                }
            }

            { Get-FfmpegPath } | Should -Throw -ExceptionType ([System.IO.FileNotFoundException]) -ExpectedMessage '未找到 FFmpeg'
        }
    }
}
