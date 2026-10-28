#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Test-UpscaleResult 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五个级别覆盖 Test-UpscaleResult：
    L1 正常流程      —— Context 'L1 正常执行路径'
    L2 异常流程      —— Context 'L2 异常流程'
    L3 边界数据      —— Context 'L3 参数契约与边界数据'
    L4 分支与循环    —— Context 'L4 分支与循环'
    L5 输出字段验证  —— Context 'L5 输出字段验证'

    该函数是纯判断函数：输入预期数量与输出目录，输出一个 bool（或抛异常）。
    L5 的「字段」即这个布尔值本身，因此以「精确值 + 类型 + 无多余输出」验证。

    夹具全部人造：
    - 配置实例在模块作用域内用 [IPAPConfiguration]::new(...) 构造，ProjectRoot 指向 TestDrive，
      支持格式固定，不读取真实 config.toml；注入走 InModuleScope 的 -Parameters 通道；
    - Test-SupportedImageFormat 保持真实（它决定「哪些文件算数」）；
    - Test-Path / Get-ChildItem / Write-LogEntry 属于外部副作用，全部 Mock。
#>

Describe 'Test-UpscaleResult Unit Tests' -Tag 'Test-UpscaleResult', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 人造配置：ProjectRoot 必须真实存在（PathConfiguration 构造函数会校验）
        [string]$Script:ConfigRoot = New-Item -ItemType Directory -Path 'TestDrive:\config-root' -Force |
            Select-Object -ExpandProperty FullName

        $Script:MockConfig = InModuleScope IPAP -Parameters @{ Root = $Script:ConfigRoot } -ScriptBlock {
            param($Root)
            $paths = [PathConfiguration]::new($Root, 'C:\Projects', 'C:\Images')
            $tools = [ToolConfiguration]::new($paths, @{})
            $app = [ApplicationConfiguration]::new(@{})
            $app.SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
            $project = [ProjectConfiguration]::new(@{})
            [IPAPConfiguration]::new($paths, $tools, $app, $project)
        }

        # 关键：用 -Parameters 传值；InModuleScope 里读不到测试作用域的变量
        InModuleScope IPAP -Parameters @{ Cfg = $Script:MockConfig } -ScriptBlock {
            param($Cfg)
            $script:IPAPConfigInstance = $Cfg
        }

        $Script:OutputDir = 'C:\output'

        Mock Write-LogEntry -ModuleName IPAP { }
        Mock Test-Path -ModuleName IPAP { return $true }
        Mock Get-ChildItem -ModuleName IPAP { return @() }
    }

    Context 'L1 正常执行路径' {
        It '实际数量等于预期时应返回 $true' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                    [PSCustomObject]@{ Name = 'image2.jpg'; Extension = '.jpg' }
                    [PSCustomObject]@{ Name = 'image3.png'; Extension = '.png' }
                )
            }

            Test-UpscaleResult -ExpectedCount 3 -OutputDir $Script:OutputDir | Should -BeTrue
        }

        It '实际数量少于预期时应返回 $false' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                    [PSCustomObject]@{ Name = 'image2.jpg'; Extension = '.jpg' }
                )
            }

            Test-UpscaleResult -ExpectedCount 5 -OutputDir $Script:OutputDir | Should -BeFalse
        }
    }

    Context 'L2 异常流程' {
        It 'ExpectedCount 为 0 时应抛出 ArgumentException 并记录 Error 日志' {
            $Thrown = $null

            try {
                Test-UpscaleResult -ExpectedCount 0 -OutputDir $Script:OutputDir
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.ArgumentException])
            $Thrown.Exception.ParamName | Should -BeExactly 'ExpectedCount'
            $Thrown.Exception.Message | Should -BeLike '*必须大于 0*'
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It 'ExpectedCount 为负数时应抛出 ArgumentException' {
            $Thrown = $null

            try {
                Test-UpscaleResult -ExpectedCount -1 -OutputDir $Script:OutputDir
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.ArgumentException])
            $Thrown.Exception.ParamName | Should -BeExactly 'ExpectedCount'
        }

        It '输出目录不存在时应抛出 DirectoryNotFoundException' {
            Mock -ModuleName IPAP Test-Path { return $false }

            $Thrown = $null
            try {
                Test-UpscaleResult -ExpectedCount 3 -OutputDir 'C:\nonexistent'
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.IO.DirectoryNotFoundException])
            $Thrown.Exception.Message | Should -BeLike '输出目录不存在*'
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It '实际输出为 0 时应抛出 InvalidOperationException' {
            Mock -ModuleName IPAP Get-ChildItem { return @() }

            $Thrown = $null
            try {
                Test-UpscaleResult -ExpectedCount 3 -OutputDir $Script:OutputDir
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.InvalidOperationException])
            $Thrown.Exception.Message | Should -BeExactly '并行处理完全失败，未生成任何输出文件'
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It 'OutputDir 为空字符串时应被参数绑定拒绝' {
            $Thrown = $null

            try {
                Test-UpscaleResult -ExpectedCount 3 -OutputDir ''
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationErrorEmptyStringNotAllowed*'
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 0 -Exactly
        }

        It 'OutputDir 为 $null 时应被参数绑定拒绝' {
            $Thrown = $null

            try {
                Test-UpscaleResult -ExpectedCount 3 -OutputDir $null
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationErrorEmptyStringNotAllowed*'
        }
    }

    Context 'L3 参数契约与边界数据' {
        It '实际数量多于预期时应返回 $false' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                    [PSCustomObject]@{ Name = 'image2.jpg'; Extension = '.jpg' }
                    [PSCustomObject]@{ Name = 'image3.jpg'; Extension = '.jpg' }
                )
            }

            Test-UpscaleResult -ExpectedCount 2 -OutputDir $Script:OutputDir | Should -BeFalse
        }

        It '应只统计支持的图片格式' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                    [PSCustomObject]@{ Name = 'image2.txt'; Extension = '.txt' }
                    [PSCustomObject]@{ Name = 'image3.png'; Extension = '.png' }
                    [PSCustomObject]@{ Name = 'image4.pdf'; Extension = '.pdf' }
                )
            }

            Test-UpscaleResult -ExpectedCount 2 -OutputDir $Script:OutputDir | Should -BeTrue
        }

        It '预期 1 且实际 1 时应返回 $true' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @([PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' })
            }

            Test-UpscaleResult -ExpectedCount 1 -OutputDir $Script:OutputDir | Should -BeTrue
        }
    }

    Context 'L4 分支与循环' {
        It '成功分支应记录 1 次 Info' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @([PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' })
            }

            $null = Test-UpscaleResult -ExpectedCount 1 -OutputDir $Script:OutputDir

            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Info' } -Times 1 -Exactly
        }

        It '部分成功分支应记录 1 次 Warning' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @([PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' })
            }

            $null = Test-UpscaleResult -ExpectedCount 3 -OutputDir $Script:OutputDir

            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' } -Times 1 -Exactly
        }

        It '成功分支不应记录 Warning 或 Error' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @([PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' })
            }

            $null = Test-UpscaleResult -ExpectedCount 1 -OutputDir $Script:OutputDir

            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -in @('Warning', 'Error') } -Times 0 -Exactly
        }
    }

    Context 'L5 输出字段验证' {
        It '返回值类型应为 System.Boolean' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @([PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' })
            }

            Test-UpscaleResult -ExpectedCount 1 -OutputDir $Script:OutputDir |
                Should -BeOfType ([System.Boolean])
            Test-UpscaleResult -ExpectedCount 3 -OutputDir $Script:OutputDir |
                Should -BeOfType ([System.Boolean])
        }

        It '单次调用应只输出一个值' {
            Mock -ModuleName IPAP Get-ChildItem {
                return @([PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' })
            }

            $Result = Test-UpscaleResult -ExpectedCount 1 -OutputDir $Script:OutputDir

            @($Result).Count | Should -Be 1
        }
    }
}
