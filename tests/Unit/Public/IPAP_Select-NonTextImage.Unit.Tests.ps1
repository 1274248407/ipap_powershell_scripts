#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Select-NonTextImage 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五个级别覆盖 Select-NonTextImage 的全部分支与输出字段：
    L1 正常流程      —— Context 'L1 正常执行路径'
    L2 异常流程      —— Context 'L2 异常流程'
    L3 边界数据      —— Context 'L3 参数契约与边界数据'
    L4 分支与循环    —— Context 'L4 分支与循环'
    L5 输出字段验证  —— Context 'L5 输出字段验证'

    该函数对外只依赖「交互输入」与「文件系统」，因此：
    - 仅 Mock Read-Host（系统命令）与 Write-LogEntry（噪声抑制，规则例外见 doc/将来要改的地方.md）；
    - Get-ImageFile / Get-NaturalSortKey / Test-SupportedImageFormat / Test-Path 全部真实运行，
      测试数据是 TestDrive 下人造的空 .jpg/.png 文件（Get-ImageFile 只按扩展名筛选，不解码图片）。
    用户输入通过 $Script:InputQueue 队列驱动；队列为空时 Mock 返回 $null，即模拟 stdin EOF，
    专门用于验证「非交互环境按跳过处理、不会无限重问」的守卫。

    返回值形状按 PowerShell 惯用语义钉住：0 项 -> $null，1 项 -> 标量 FileInfo，N 项 -> FileInfo[]。
    生产调用点 Start-IPAPWorkflow 用 .Count 与 @() 消费，三种形状均可正常工作。
#>

Describe 'Select-NonTextImage Unit Tests' -Tag 'Select-NonTextImage', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 共享工作根目录：所有夹具都放在它下面，AfterEach 一次性清理
        [string]$Script:WorkRoot = New-Item -ItemType Directory -Path 'TestDrive:\work' -Force |
            Select-Object -ExpandProperty FullName

        # 主目录：1.jpg / 2.jpg / 10.jpg（用于验证自然排序：词法序会是 1,10,2）+ 非图片文件
        [string]$Script:SourceDir = New-Item -ItemType Directory -Path (Join-Path $Script:WorkRoot 'source') -Force |
            Select-Object -ExpandProperty FullName
        foreach ($Name in @('1.jpg', '2.jpg', '10.jpg', 'note.txt')) {
            New-Item -ItemType File -Path (Join-Path $Script:SourceDir $Name) -Force | Out-Null
        }

        # 自定义路径模式用的另一个目录
        [string]$Script:CustomDir = New-Item -ItemType Directory -Path (Join-Path $Script:WorkRoot 'custom') -Force |
            Select-Object -ExpandProperty FullName
        New-Item -ItemType File -Path (Join-Path $Script:CustomDir '5.jpg') -Force | Out-Null

        $Script:Formats = @('.jpg', '.png')
        $Script:InputQueue = [System.Collections.Generic.Queue[string]]::new()

        # 静默内部日志函数（纯噪声抑制）
        Mock Write-LogEntry -ModuleName IPAP { }

        # 交互输入：按用例预先入队；队列空即模拟 stdin EOF（返回 $null）
        Mock Read-Host -ModuleName IPAP {
            if ($Script:InputQueue.Count -eq 0) {
                return $null
            }
            return $Script:InputQueue.Dequeue()
        }
    }

    AfterEach {
        if ($Script:WorkRoot -and (Test-Path -LiteralPath $Script:WorkRoot)) {
            Remove-Item -LiteralPath $Script:WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'L1 正常执行路径' {
        It '模式 1（起始编号）输入 2 时应返回第 2 张及之后的图片' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('2')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            @($Result).Count | Should -Be 2
            (@($Result).Name -join ',') | Should -BeExactly '2.jpg,10.jpg'
        }

        It '模式 4（跳过）应返回 $null' {
            # 无子文件夹时菜单为 3 项：[1] 起始编号 [2] 自定义路径 [3] 跳过
            $Script:InputQueue.Enqueue('3')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
        }

        It '提供 -PreSortedImages 时应直接使用给定集合而不重新扫描' {
            $Presorted = @(Get-ChildItem -LiteralPath $Script:SourceDir -File |
                    Where-Object { $PSItem.Extension -eq '.jpg' } |
                    Sort-Object -Property Name -Descending)
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('1')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats -PreSortedImages $Presorted

            # 顺序与传入集合完全一致（若重新扫描会变成自然序 1,2,10）
            (@($Result).Name -join ',') | Should -BeExactly ($Presorted.Name -join ',')
        }

        It '模式 3（自定义路径）应返回该目录下的图片' {
            $Script:InputQueue.Enqueue('2')
            $Script:InputQueue.Enqueue($Script:CustomDir)

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            @($Result).Count | Should -Be 1
            @($Result)[0].Name | Should -BeExactly '5.jpg'
        }
    }

    Context 'L2 异常流程' {
        It '源目录不存在时应抛出 ArgumentException 并记录 Error 日志' {
            $MissingDir = Join-Path $Script:WorkRoot 'missing'
            $Thrown = $null

            try {
                Select-NonTextImage -SourceDir $MissingDir -SupportedImageFormats $Script:Formats
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.ArgumentException])
            $Thrown.Exception.Message | Should -BeLike '源目录不存在*'
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It '选项输入非数字时应警告并重问，直到收到合法值' {
            $Script:InputQueue.Enqueue('abc')
            $Script:InputQueue.Enqueue('3')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -eq '请输入有效的数字' } -Times 1 -Exactly
        }

        It '自定义路径不存在时应警告并重问' {
            $MissingDir = Join-Path $Script:WorkRoot 'missing'
            $Script:InputQueue.Enqueue('2')
            $Script:InputQueue.Enqueue($MissingDir)
            $Script:InputQueue.Enqueue($Script:CustomDir)

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            @($Result).Count | Should -Be 1
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '路径不存在: *' } -Times 1 -Exactly
        }
    }

    Context 'L3 参数契约与边界数据' {
        It 'SourceDir 为空字符串时应被参数绑定拒绝' {
            { Select-NonTextImage -SourceDir '' -SupportedImageFormats $Script:Formats } |
                Should -Throw '*SourceDir*'
        }

        It '起始编号为 1 时应返回全部图片' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('1')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            @($Result).Count | Should -Be 3
        }

        It '起始编号为末位时应只返回一张且结果为标量' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('3')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            $Result | Should -Not -BeNullOrEmpty
            $Result.Name | Should -BeExactly '10.jpg'
            # PowerShell 会把单元素数组展开为标量（调用方用 @() 包裹即可）
            ($Result -is [array]) | Should -BeFalse
        }

        It '-PreSortedImages 为空数组时应回落为扫描目录' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('1')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats -PreSortedImages @()

            @($Result).Count | Should -Be 3
        }

        It '目录内没有图片时输入 0 应跳过' {
            [string]$EmptyDir = New-Item -ItemType Directory -Path (Join-Path $Script:WorkRoot 'empty') -Force |
                Select-Object -ExpandProperty FullName
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('0')

            $Result = Select-NonTextImage -SourceDir $EmptyDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
        }

        It '目录内只有一张图片时结果为标量' {
            [string]$SingleDir = New-Item -ItemType Directory -Path (Join-Path $Script:WorkRoot 'single') -Force |
                Select-Object -ExpandProperty FullName
            New-Item -ItemType File -Path (Join-Path $SingleDir '002.jpg') -Force | Out-Null
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('1')

            $Result = Select-NonTextImage -SourceDir $SingleDir -SupportedImageFormats $Script:Formats

            $Result.Name | Should -BeExactly '002.jpg'
            ($Result -is [array]) | Should -BeFalse
        }

        It '-PreSortedImages 只给两项时起始编号上限应按两项计算' {
            $Presorted = @(Get-ChildItem -LiteralPath $Script:SourceDir -File |
                    Where-Object { $PSItem.Extension -eq '.jpg' } |
                    Sort-Object -Property Name |
                    Select-Object -First 2)
            # 99 越界 -> 重问；2 合法 -> 返回最后一张
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('99')
            $Script:InputQueue.Enqueue('2')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats -PreSortedImages $Presorted

            @($Result).Count | Should -Be 1
            $Result.Name | Should -BeExactly '10.jpg'
            # 提示里的上限应反映「传入的两项」而不是目录里的三张
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -eq '请输入 0 到 2 之间的数字' } -Times 1 -Exactly
        }
    }

    Context 'L4 分支与循环' {
        It '存在子文件夹时菜单为 4 项，模式 2 应能选中子文件夹' {
            [string]$SubDir = New-Item -ItemType Directory -Path (Join-Path $Script:SourceDir 'sub') -Force |
                Select-Object -ExpandProperty FullName
            foreach ($Name in @('a.jpg', 'b.jpg')) {
                New-Item -ItemType File -Path (Join-Path $SubDir $Name) -Force | Out-Null
            }
            $Script:InputQueue.Enqueue('2')
            $Script:InputQueue.Enqueue('1')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            @($Result).Count | Should -Be 2
            @($Result)[0].DirectoryName | Should -BeExactly $SubDir
        }

        It '存在子文件夹时编号后移：输入 3 应进入自定义路径模式' {
            # 让函数发现一个子文件夹，从而让菜单中的“自定义路径”选项编号变成 3。
            # 删掉后，测试输入 3 会选到“跳过”
            New-Item -ItemType Directory -Path (Join-Path $Script:SourceDir 'sub') -Force |
                Select-Object -ExpandProperty FullName
            # New-Item -ItemType File -Path (Join-Path $SubDir 'a.jpg') -Force | Out-Null
            $Script:InputQueue.Enqueue('3')
            $Script:InputQueue.Enqueue($Script:CustomDir)

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            @($Result).Count | Should -Be 1
            @($Result)[0].Name | Should -BeExactly '5.jpg'
        }

        It '选项输入越界（0 与 99）时应各提示一次并重问' {
            $Script:InputQueue.Enqueue('0')
            $Script:InputQueue.Enqueue('99')
            $Script:InputQueue.Enqueue('3')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
            Should -Invoke -ModuleName IPAP Read-Host -Times 3 -Exactly
            # 越界不是「静默重问」：每一次越界都必须给出提示
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '请输入 * 到 * 之间的数字' } -Times 2 -Exactly
        }

        It '模式 1 输入 0 应跳过并记录 Info 日志' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('0')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Message -eq '用户跳过无文字图处理' } -Times 1 -Exactly
        }

        It '模式 1 起始编号越界时应提示并重问' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('99')
            $Script:InputQueue.Enqueue('2')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            @($Result).Count | Should -Be 2
            # 起始编号的合法范围是 0..Count（0 表示跳过）
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -eq '请输入 0 到 3 之间的数字' } -Times 1 -Exactly
        }

        It '模式 2 文件夹选择越界时应提示并重问' {
            [string]$SubDir = New-Item -ItemType Directory -Path (Join-Path $Script:SourceDir 'sub') -Force |
                Select-Object -ExpandProperty FullName
            New-Item -ItemType File -Path (Join-Path $SubDir 'a.jpg') -Force | Out-Null
            $Script:InputQueue.Enqueue('2')
            $Script:InputQueue.Enqueue('0')
            $Script:InputQueue.Enqueue('1')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            @($Result).Count | Should -Be 1
            # 只有一个子文件夹，0 越界
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -eq '请输入 1 到 1 之间的数字' } -Times 1 -Exactly
        }

        It '选中的子文件夹没有图片时应警告并返回 $null' {
            [string]$EmptySubDir = New-Item -ItemType Directory -Path (Join-Path $Script:SourceDir 'emptysub') -Force |
                Select-Object -ExpandProperty FullName
            $Script:InputQueue.Enqueue('2')
            $Script:InputQueue.Enqueue('1')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Message -eq '未找到任何无文字图' } -Times 1 -Exactly
        }

        It '菜单处遇到 EOF（stdin 结束）应按跳过处理而不是死循环' {
            # 队列为空，Read-Host 返回 $null
            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Message -eq '未读到输入（非交互环境），按跳过处理' } -Times 1 -Exactly
        }

        It '自定义路径处遇到 EOF 应按跳过处理而不是死循环' {
            $Script:InputQueue.Enqueue('2')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Message -eq '未读到输入（非交互环境），按跳过处理' } -Times 1 -Exactly
        }

        It '图片多于预览两倍时应输出后 5 张预览' {
            [string]$ManyDir = New-Item -ItemType Directory -Path (Join-Path $Script:WorkRoot 'many') -Force |
                Select-Object -ExpandProperty FullName
            foreach ($Index in 1..11) {
                New-Item -ItemType File -Path (Join-Path $ManyDir ("{0}.jpg" -f $Index)) -Force | Out-Null
            }
            $Script:InputQueue.Enqueue('3')

            $null = Select-NonTextImage -SourceDir $ManyDir -SupportedImageFormats $Script:Formats

            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Message -like '*后 5 张*' } -Times 1 -Exactly
        }

        It '图片不超过预览两倍时不应输出后 5 张预览' {
            $Script:InputQueue.Enqueue('3')

            $null = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Message -like '*后 5 张*' } -Times 0 -Exactly
        }
    }

    Context 'L5 输出字段验证' {
        It '返回元素应为 System.IO.FileInfo' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('1')

            $Result = @(Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats)

            $Result.Count | Should -Be 3
            $Result[0] | Should -BeOfType ([System.IO.FileInfo])
        }

        It '每一项的 Name 与 Extension 应精确' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('1')

            $Result = @(Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats)

            $Result[0].Name | Should -BeExactly '1.jpg'
            $Result[0].Extension | Should -BeExactly '.jpg'
            $Result[2].Name | Should -BeExactly '10.jpg'
        }

        It '应按自然排序输出 1.jpg、2.jpg、10.jpg' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('1')

            $Result = @(Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats)

            $Result[0].Name | Should -BeExactly '1.jpg'
            $Result[1].Name | Should -BeExactly '2.jpg'
            $Result[2].Name | Should -BeExactly '10.jpg'
        }

        It '每一项的 FullName 应真实存在且位于源目录下' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('2')

            $Result = @(Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats)

            foreach ($File in $Result) {
                (Test-Path -LiteralPath $File.FullName) | Should -BeTrue
                (Split-Path -Parent $File.FullName) | Should -BeExactly $Script:SourceDir
            }
        }

        It '非图片文件不应出现在结果中' {
            $Script:InputQueue.Enqueue('1')
            $Script:InputQueue.Enqueue('1')

            $Result = @(Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats)

            (@($Result).Name -contains 'note.txt') | Should -BeFalse
            $Result.Count | Should -Be 3
        }

        It '跳过时结果应为 $null 而不是空数组' {
            $Script:InputQueue.Enqueue('3')

            $Result = Select-NonTextImage -SourceDir $Script:SourceDir -SupportedImageFormats $Script:Formats

            ($null -eq $Result) | Should -BeTrue
        }
    }
}
