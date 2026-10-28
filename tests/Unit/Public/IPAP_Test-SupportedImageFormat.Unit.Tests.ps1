#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Test-SupportedImageFormat 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五个级别覆盖 Test-SupportedImageFormat：
    L1 正常流程      —— Context 'L1 正常执行路径'
    L2 异常流程      —— Context 'L2 异常流程'
    L3 边界数据      —— Context 'L3 参数契约与边界数据'
    L4 分支与循环    —— Context 'L4 分支与循环'
    L5 输出字段验证  —— Context 'L5 输出字段验证'

    该函数是纯判断函数：输入一个对象、输出一个 bool（管道输入时逐对象输出）。
    L5 的「字段」即这个布尔值本身，因此以「精确值 + 类型 + 管道顺序」验证。

    夹具全部人造：
    - 配置实例在模块作用域内用 [IPAPConfiguration]::new(...) 构造，ProjectRoot 指向 TestDrive，
      随后把 App.SupportedImageFormats 赋成固定列表，不读取真实 config.toml；
    - 配置注入走 InModuleScope 的 -Parameters 通道；
    - Get-SupportedImageFormat 与 Get-Configuration 保持真实，以覆盖「未传 -SupportedFormats 就读配置」分支。
#>

Describe 'Test-SupportedImageFormat Unit Tests' -Tag 'Test-SupportedImageFormat', 'IPAP' {
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
            $app.SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff')
            $project = [ProjectConfiguration]::new(@{})
            [IPAPConfiguration]::new($paths, $tools, $app, $project)
        }

        InModuleScope IPAP -Parameters @{ Cfg = $Script:MockConfig } -ScriptBlock {
            param($Cfg)
            $script:IPAPConfigInstance = $Cfg
        }

        Mock Write-LogEntry -ModuleName IPAP { }

        # 人造文件对象：该函数只读取 Extension 属性
        $Script:Jpg = [PSCustomObject]@{ Name = 'a.jpg'; Extension = '.jpg' }
        $Script:Txt = [PSCustomObject]@{ Name = 'a.txt'; Extension = '.txt' }
        $Script:Png = [PSCustomObject]@{ Name = 'a.png'; Extension = '.png' }
    }

    Context 'L1 正常执行路径' {
        It '扩展名在配置列表中时应返回 $true' {
            Test-SupportedImageFormat -File $Script:Jpg | Should -BeTrue
        }

        It '扩展名不在配置列表中时应返回 $false' {
            Test-SupportedImageFormat -File $Script:Txt | Should -BeFalse
        }
    }

    Context 'L2 异常流程' {
        It 'Extension 为非字符串时应抛出 ArgumentException 并记录 Error 日志' {
            $File = [PSCustomObject]@{ Name = 'x'; Extension = 123 }
            $Thrown = $null

            try {
                Test-SupportedImageFormat -File $File
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.ArgumentException])
            $Thrown.Exception.Message | Should -BeLike '*Extension*'
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It '配置未初始化且未传 -SupportedFormats 时应抛出 InvalidOperationException' {
            InModuleScope IPAP { $script:IPAPConfigInstance = $null }
            $Thrown = $null

            try {
                Test-SupportedImageFormat -File $Script:Jpg
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.InvalidOperationException])
        }
    }

    Context 'L3 参数契约与边界数据' {
        It '缺少 Extension 属性时应返回 $false 并记录 Warning 日志' {
            $File = [PSCustomObject]@{ Name = 'test.jpg' }

            Test-SupportedImageFormat -File $File | Should -BeFalse
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -eq '输入对象缺少 Extension 属性' } -Times 1 -Exactly
        }

        It 'Extension 为 $null 时应返回 $false' {
            $File = [PSCustomObject]@{ Name = 'test'; Extension = $null }

            Test-SupportedImageFormat -File $File | Should -BeFalse
        }

        It 'Extension 为空字符串时应返回 $false' {
            $File = [PSCustomObject]@{ Name = 'test'; Extension = '' }

            Test-SupportedImageFormat -File $File | Should -BeFalse
        }

        It '扩展名为大写时应返回 $true（大小写不敏感）' {
            $File = [PSCustomObject]@{ Name = 'test.JPG'; Extension = '.JPG' }

            Test-SupportedImageFormat -File $File | Should -BeTrue
        }

        It '扩展名带首尾空格时应返回 $false（不做 trim）' {
            $File = [PSCustomObject]@{ Name = 'test'; Extension = ' .jpg ' }

            Test-SupportedImageFormat -File $File | Should -BeFalse
        }

        It '显式传空数组时应返回 $false 且不回退到配置' {
            Test-SupportedImageFormat -File $Script:Jpg -SupportedFormats @() | Should -BeFalse
        }
    }

    Context 'L4 分支与循环' {
        It '未传 -SupportedFormats 时应使用配置中的格式列表' {
            InModuleScope IPAP {
                $script:IPAPConfigInstance.App.SupportedImageFormats = @('.png')
            }

            Test-SupportedImageFormat -File $Script:Jpg | Should -BeFalse
            Test-SupportedImageFormat -File $Script:Png | Should -BeTrue
        }

        It '传 -SupportedFormats 时应覆盖配置中的格式列表' {
            Test-SupportedImageFormat -File $Script:Jpg -SupportedFormats @('.png') | Should -BeFalse
            Test-SupportedImageFormat -File $Script:Png -SupportedFormats @('.png') | Should -BeTrue
        }

        It '管道输入时每个对象都应使用同一份显式格式列表' {
            $Results = @($Script:Jpg, $Script:Txt) | Test-SupportedImageFormat -SupportedFormats @('.txt')

            @($Results).Count | Should -Be 2
            @($Results)[0] | Should -BeFalse
            @($Results)[1] | Should -BeTrue
        }
    }

    Context 'L5 输出字段验证' {
        It '返回值类型应为 System.Boolean' {
            Test-SupportedImageFormat -File $Script:Jpg | Should -BeOfType ([System.Boolean])
            Test-SupportedImageFormat -File $Script:Txt | Should -BeOfType ([System.Boolean])
        }

        It '管道多对象应返回与输入顺序一致的布尔序列' {
            $Results = @($Script:Jpg, $Script:Txt, $Script:Png) | Test-SupportedImageFormat

            @($Results).Count | Should -Be 3
            @($Results)[0] | Should -BeTrue
            @($Results)[1] | Should -BeFalse
            @($Results)[2] | Should -BeTrue
        }

        It '管道单对象应返回标量布尔而非数组' {
            $Result = $Script:Jpg | Test-SupportedImageFormat

            $Result | Should -BeOfType ([System.Boolean])
            ($Result -is [array]) | Should -BeFalse
        }
    }
}
