#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ImageLevel 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖编排层：
    L1 单图、L3 空列表、L4 并行结果排序与计数、L5 输出字段。
    单图分析逻辑（分辨率、YDIF、阈值）由 Get-ImageLevelForImage 的单测覆盖；
    本文件只验证路径解析、索引恢复、计数与日志。
#>

Describe 'Get-ImageLevel Unit Tests' -Tag 'Get-ImageLevel', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock -CommandName Write-LogEntry -ModuleName IPAP { }
        # 假工具路径：worker 内部的 & 调用会抛异常，从而稳定走 Level 1 回退路径
        Mock -CommandName Get-FfprobePath -ModuleName IPAP { return 'C:\fake\ffprobe.exe' }
        Mock -CommandName Get-FfmpegPath -ModuleName IPAP { return 'C:\fake\ffmpeg.exe' }

        $script:Images = @(
            [PSCustomObject]@{ FullName = 'D:\images\a.png' }
            [PSCustomObject]@{ FullName = 'D:\images\b.png' }
        )
    }

    Context 'L3 空列表' {
        It '空图片数组应无输出且记录 0 计数' {
            $result = Get-ImageLevel -Images @()

            $result | Should -BeNullOrEmpty
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter { $Message -eq '开始分析 0 张图片的质量分级...' } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter { $Message -eq '图片分级分析完成: 0 张' } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter { $Message -eq '分级结果 - Level 0 (高清跳过): 0, Level 1 (FFmpeg): 0, Level 2 (Real-CUGAN): 0' } -Times 1 -Exactly
        }
    }

    Context 'L1 单图' {
        It '单图应返回一个五字段完整的结果' {
            $result = @(Get-ImageLevel -Images @($script:Images[0]))

            $result.Count | Should -Be 1
            $result[0].Index | Should -Be 0
            $result[0].Image | Should -Be $script:Images[0]
            $result[0].Level | Should -Be 1
            $result[0].LongEdge | Should -Be 0
            $result[0].YDIF | Should -Be 5.0
        }

        It '应各调用一次工具路径解析' {
            $null = Get-ImageLevel -Images @($script:Images[0])

            Should -Invoke -CommandName Get-FfprobePath -ModuleName IPAP -Times 1 -Exactly
            Should -Invoke -CommandName Get-FfmpegPath -ModuleName IPAP -Times 1 -Exactly
        }
    }

    Context 'L4 并行结果排序与计数' {
        It '多图应按原始 Index 恢复顺序' {
            $result = @(Get-ImageLevel -Images $script:Images)

            $result.Count | Should -Be 2
            $result[0].Index | Should -Be 0
            $result[1].Index | Should -Be 1
            $result[0].Image | Should -Be $script:Images[0]
            $result[1].Image | Should -Be $script:Images[1]
        }

        It '应记录开始、完成与分级计数日志' {
            $null = Get-ImageLevel -Images $script:Images

            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter { $Message -eq '开始分析 2 张图片的质量分级...' } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter { $Message -eq '图片分级分析完成: 2 张' } -Times 1 -Exactly
            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter { $Message -eq '分级结果 - Level 0 (高清跳过): 0, Level 1 (FFmpeg): 2, Level 2 (Real-CUGAN): 0' } -Times 1 -Exactly
        }
    }
}
