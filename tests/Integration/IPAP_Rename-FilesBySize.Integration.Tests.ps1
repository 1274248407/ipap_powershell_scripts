#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Rename-FilesBySize 集成测试
.DESCRIPTION
    使用 Pester TestDrive 提供的真实文件系统，验证 Rename-FilesBySize 与文件系统的协作行为：
    按文件大小降序连续重命名（保留原扩展名）、返回值语义、-StartIndex 起始编号、
    相同大小文件的批次完整性、失败守卫。
    通过 [System.IO.File]::WriteAllBytes 写入指定长度的随机字节构造真实图片文件，
    通过 Get-Configuration 指向 TestDrive 物理根目录（无 config.toml）走默认配置分支，
    不涉及任何外部工具的真实执行。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'Rename-FilesBySize 集成测试（真实文件系统协作）' -Tag 'Integration' {
    BeforeAll {
        # tests\Integration → 项目根（向上两级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # TestDrive 的物理根路径（Pester 管理的隔离临时目录）
        [string]$Script:TestDriveRoot = (Get-PSDrive -Name TestDrive).Root

        # 日志函数 Mock：Write-LogEntry 为纯日志函数，全级别静默记录
        Mock Write-LogEntry -ModuleName IPAP { }


        # 初始化配置：TestDrive 根下无 config.toml → ReadConfigFile 回退默认值分支
        #（Rename-FilesBySize 内部依赖 Test-SupportedImageFormat 从配置读取支持的格式）
        Get-Configuration -ProjectRoot $Script:TestDriveRoot | Out-Null
    }

    AfterAll {
        # 清理模块内配置实例与模块，防止污染其他测试
        InModuleScope IPAP { $script:IPAPConfigInstance = $null }
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常路径 - 按大小降序重命名' {
        It '应按大小降序连续重命名并保留原扩展名' {
            [string]$CaseDir = Join-Path $Script:TestDriveRoot 'rename_desc'
            New-Item -ItemType Directory -Path $CaseDir | Out-Null

            # 文件大小计划：another.jpg(4000) > big.jpg(3000) > mid.png(2000) > small.webp(1000)
            [hashtable]$FilePlan = @{ 'big.jpg' = 3000; 'mid.png' = 2000; 'small.webp' = 1000; 'another.jpg' = 4000 }
            foreach ($entry in $FilePlan.GetEnumerator())
            {
                # 写入指定长度的随机字节真实文件
                [byte[]]$Buffer = [byte[]]::new([int]$entry.Value)
                ([System.Random]::new()).NextBytes($Buffer)
                [System.IO.File]::WriteAllBytes((Join-Path $CaseDir $entry.Key), $Buffer)
            }

            [int]$Result = Rename-FilesBySize -Directory $CaseDir

            # 返回值等于文件数
            $Result | Should -Be 4

            # 重命名后文件名按大小降序连续编号，且保留原扩展名
            [string[]]$ActualNames = (Get-ChildItem -LiteralPath $CaseDir -File | Sort-Object Name).Name
            $ActualNames | Should -Be @('1.jpg', '2.jpg', '3.png', '4.webp')

            # 验证编号与文件大小的对应关系（降序）
            [hashtable]$SizeByName = @{}
            foreach ($file in (Get-ChildItem -LiteralPath $CaseDir -File))
            {
                $SizeByName[$file.Name] = [int]$file.Length
            }
            $SizeByName['1.jpg'] | Should -Be 4000
            $SizeByName['2.jpg'] | Should -Be 3000
            $SizeByName['3.png'] | Should -Be 2000
            $SizeByName['4.webp'] | Should -Be 1000
        }

        It '-StartIndex 应从指定编号开始命名' {
            [string]$CaseDir = Join-Path $Script:TestDriveRoot 'rename_start_index'
            New-Item -ItemType Directory -Path $CaseDir | Out-Null

            # 3 个不同大小的图片文件
            [hashtable]$FilePlan = @{ 'b.jpg' = 2500; 'a.png' = 1500; 'c.webp' = 500 }
            foreach ($entry in $FilePlan.GetEnumerator())
            {
                [byte[]]$Buffer = [byte[]]::new([int]$entry.Value)
                ([System.Random]::new()).NextBytes($Buffer)
                [System.IO.File]::WriteAllBytes((Join-Path $CaseDir $entry.Key), $Buffer)
            }

            [int]$Result = Rename-FilesBySize -Directory $CaseDir -StartIndex 5

            # 从 5 开始连续编号
            $Result | Should -Be 3
            [string[]]$ActualNames = (Get-ChildItem -LiteralPath $CaseDir -File | Sort-Object Name).Name
            $ActualNames | Should -Be @('5.jpg', '6.png', '7.webp')
        }

        It '相同大小的文件也应全部被连续编号（不对排序稳定性做假设）' {
            [string]$CaseDir = Join-Path $Script:TestDriveRoot 'rename_tie'
            New-Item -ItemType Directory -Path $CaseDir | Out-Null

            # 2 个相同大小的 jpg 文件（大小相同则先后顺序不确定，不断言具体哪个对应哪个编号）
            [byte[]]$Buffer1 = [byte[]]::new(1000)
            [byte[]]$Buffer2 = [byte[]]::new(1000)
            ([System.Random]::new()).NextBytes($Buffer1)
            ([System.Random]::new()).NextBytes($Buffer2)
            [System.IO.File]::WriteAllBytes((Join-Path $CaseDir 'first.jpg'), $Buffer1)
            [System.IO.File]::WriteAllBytes((Join-Path $CaseDir 'second.jpg'), $Buffer2)

            [int]$Result = Rename-FilesBySize -Directory $CaseDir

            # 全部重命名成功且编号连续、字节总量守恒
            $Result | Should -Be 2
            [string[]]$ActualNames = (Get-ChildItem -LiteralPath $CaseDir -File | Sort-Object Name).Name
            $ActualNames | Should -Be @('1.jpg', '2.jpg')
            [int]$SizeSum = (Get-ChildItem -LiteralPath $CaseDir -File | Measure-Object -Property Length -Sum).Sum
            $SizeSum | Should -Be 2000
        }
    }

    Context '失败路径' {
        It '目录不存在时应记录错误并抛出终止错误' {
            [string]$MissingDir = Join-Path $Script:TestDriveRoot 'no_such_rename_dir'

            { Rename-FilesBySize -Directory $MissingDir } | Should -Throw '目录不存在*'
        }
    }
}
