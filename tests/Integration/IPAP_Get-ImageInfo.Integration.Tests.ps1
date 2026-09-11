#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ImageInfo 集成测试
.DESCRIPTION
    使用 Pester TestDrive 提供的真实文件系统，验证 Get-ImageInfo 与文件系统的协作行为：
    真实文件扫描统计（Count/TotalSize/AverageSize）、扩展名过滤、非递归扫描、失败守卫。
    通过 Get-Configuration 指向 TestDrive 物理根目录（无 config.toml）走默认配置分支，
    规避 TOML 解析与外部工具依赖。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'Get-ImageInfo 集成测试（真实文件系统协作）' -Tag 'Integration' {
    BeforeAll {
        # tests\Integration → 项目根（向上两级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # TestDrive 的物理根路径（Pester 管理的隔离临时目录）
        [string]$Script:TestDriveRoot = (Get-PSDrive -Name TestDrive).Root

        # 日志函数 Mock：Write-LogEntry 为纯日志函数，全级别静默记录
        Mock Write-LogEntry -ModuleName IPAP { }


        # 初始化配置：TestDrive 根下无 config.toml → ReadConfigFile 回退默认值分支
        #（默认 SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')）
        Get-Configuration -ProjectRoot $Script:TestDriveRoot | Out-Null
    }

    AfterAll {
        # 清理模块内配置实例与模块，防止污染其他测试
        InModuleScope IPAP { $script:IPAPConfigInstance = $null }
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常路径 - 真实文件扫描统计' {
        It '应统计顶层图片的数量与总字节数（1024 + 2048 = 3072）' {
            [string]$SourceDir = Join-Path $Script:TestDriveRoot 'scan_basic'
            New-Item -ItemType Directory -Path $SourceDir | Out-Null

            # 写入指定长度的真实文件：a.jpg 1024 字节、b.png 2048 字节
            [byte[]]$Buffer1KB = [byte[]]::new(1024)
            [byte[]]$Buffer2KB = [byte[]]::new(2048)
            ([System.Random]::new()).NextBytes($Buffer1KB)
            ([System.Random]::new()).NextBytes($Buffer2KB)
            [System.IO.File]::WriteAllBytes((Join-Path $SourceDir 'a.jpg'), $Buffer1KB)
            [System.IO.File]::WriteAllBytes((Join-Path $SourceDir 'b.png'), $Buffer2KB)

            $Result = Get-ImageInfo -SourceDir $SourceDir

            # Count 与 TotalSize 数值验证
            [int]$Result.Count | Should -Be 2
            [int]$Result.TotalSize | Should -Be 3072
        }

        It '应正确计算平均大小（3072 / 1024 / 2 = 1.5 KB）' {
            [string]$SourceDir = Join-Path $Script:TestDriveRoot 'scan_avg'
            New-Item -ItemType Directory -Path $SourceDir | Out-Null

            [byte[]]$Buffer1KB = [byte[]]::new(1024)
            [byte[]]$Buffer2KB = [byte[]]::new(2048)
            ([System.Random]::new()).NextBytes($Buffer1KB)
            ([System.Random]::new()).NextBytes($Buffer2KB)
            [System.IO.File]::WriteAllBytes((Join-Path $SourceDir 'a.jpg'), $Buffer1KB)
            [System.IO.File]::WriteAllBytes((Join-Path $SourceDir 'b.png'), $Buffer2KB)

            $Result = Get-ImageInfo -SourceDir $SourceDir

            # AverageSize 以 KB 为单位（源码：totalSize / 1024 / count）
            [double]$Result.AverageSize | Should -Be 1.5
        }

        It '应排除不支持的扩展名（.txt）' {
            [string]$SourceDir = Join-Path $Script:TestDriveRoot 'scan_filter'
            New-Item -ItemType Directory -Path $SourceDir | Out-Null

            # 写入 1 张支持格式图片与 1 个不支持格式文件
            [byte[]]$Buffer1KB = [byte[]]::new(1024)
            [byte[]]$Buffer5KB = [byte[]]::new(5000)
            ([System.Random]::new()).NextBytes($Buffer1KB)
            ([System.Random]::new()).NextBytes($Buffer5KB)
            [System.IO.File]::WriteAllBytes((Join-Path $SourceDir 'a.jpg'), $Buffer1KB)
            [System.IO.File]::WriteAllBytes((Join-Path $SourceDir 'note.txt'), $Buffer5KB)

            $Result = Get-ImageInfo -SourceDir $SourceDir

            # .txt 不计入统计（源码通过 Test-SupportedImageFormat 过滤）
            [int]$Result.Count | Should -Be 1
            $Result.Images.Name | Should -Contain 'a.jpg'
            $Result.Images.Name | Should -Not -Contain 'note.txt'
            [int]$Result.TotalSize | Should -Be 1024
        }

        It '不应递归统计子目录中的图片（以源码 Get-ChildItem -File 非递归行为为准）' {
            [string]$SourceDir = Join-Path $Script:TestDriveRoot 'scan_non_recursive'
            New-Item -ItemType Directory -Path $SourceDir | Out-Null
            [string]$SubDir = Join-Path $SourceDir 'sub'
            New-Item -ItemType Directory -Path $SubDir | Out-Null

            # 顶层 1 张 + 子目录 1 张（子目录中的图片不应被统计）
            [byte[]]$Buffer1KB = [byte[]]::new(1024)
            [byte[]]$Buffer2KB = [byte[]]::new(2048)
            ([System.Random]::new()).NextBytes($Buffer1KB)
            ([System.Random]::new()).NextBytes($Buffer2KB)
            [System.IO.File]::WriteAllBytes((Join-Path $SourceDir 'top.jpg'), $Buffer1KB)
            [System.IO.File]::WriteAllBytes((Join-Path $SubDir 'inner.jpg'), $Buffer2KB)

            $Result = Get-ImageInfo -SourceDir $SourceDir

            # 只统计顶层文件
            [int]$Result.Count | Should -Be 1
            [int]$Result.TotalSize | Should -Be 1024
        }

        It '空目录时应返回零统计' {
            [string]$SourceDir = Join-Path $Script:TestDriveRoot 'scan_empty'
            New-Item -ItemType Directory -Path $SourceDir | Out-Null

            $Result = Get-ImageInfo -SourceDir $SourceDir

            [int]$Result.Count | Should -Be 0
            [int]$Result.TotalSize | Should -Be 0
            [double]$Result.AverageSize | Should -Be 0
        }
    }

    Context '失败路径' {
        It '目录不存在时应记录错误并抛出终止错误' {
            [string]$MissingDir = Join-Path $Script:TestDriveRoot 'no_such_scan_dir'

            { Get-ImageInfo -SourceDir $MissingDir } | Should -Throw '源目录不存在*'
        }
    }
}
