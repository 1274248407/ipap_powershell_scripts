#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Start-IPAPWorkflow 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五个级别覆盖 Start-IPAPWorkflow：
    L1 正常流程      —— Context 'L1 正常执行路径'
    L2 异常流程      —— Context 'L2 异常流程'
    L3 边界数据      —— Context 'L3 参数契约与边界数据'
    L4 分支与循环    —— Context 'L4 分支与循环'
    L5 输出字段验证  —— Context 'L5 调用契约验证'

    该函数是编排器：[OutputType([void])]，没有返回值，输出全部体现为
    「对协作者的调用」与「抛出的异常」。因此 L5 验证的是协作调用契约
    （Engine / OutputDir / Images / NeedUpscale / ExpectedCount 等），而不是返回值字段。

    夹具全部人造：
    - 配置实例在模块作用域内用 [IPAPConfiguration]::new(...) 构造，ProjectRoot 指向 TestDrive，
      不读取真实 config.toml；配置注入走 InModuleScope 的 -Parameters 通道（不要把测试作用域变量
      直接写进模块作用域，那样只会拿到 $null）。
    - 协作者全部 Mock：编排器必然串联 ffmpeg / Real-CUGAN 等外部进程，单测无法真实执行。
    - 但 Test-ConfigurationInitialized 与 Get-Configuration 保持真实，以覆盖配置守卫分支。
#>

Describe 'Start-IPAPWorkflow Unit Tests' -Tag 'Start-IPAPWorkflow', 'IPAP' {
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
            $tools.RealCuganExePath = 'C:\bin\realcugan-ncnn-vulkan.exe'
            $app = [ApplicationConfiguration]::new(@{})
            $app.MaxWorkers = 8
            $project = [ProjectConfiguration]::new(@{})
            $project.Author = 'TestAuthor'
            $project.OriginalTitle = 'TestTitle'
            $project.ChineseTitle = '测试标题'
            [IPAPConfiguration]::new($paths, $tools, $app, $project)
        }

        # 关键：用 -Parameters 传值；InModuleScope 里读不到测试作用域的 $Script: 变量
        InModuleScope IPAP -Parameters @{ Cfg = $Script:MockConfig } -ScriptBlock {
            param($Cfg)
            $script:IPAPConfigInstance = $Cfg
        }

        # 共享基础数据
        $Script:Image1 = [PSCustomObject]@{ Name = '1.jpg'; FullName = 'C:\src\1.jpg' }
        $Script:Image2 = [PSCustomObject]@{ Name = '2.jpg'; FullName = 'C:\src\2.jpg' }
        $Script:Images = @($Script:Image1, $Script:Image2)
        $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 0 }
        $Script:ProjectDir = 'C:\Projects\2026-01-01_TestProject'

        Mock Write-LogEntry -ModuleName IPAP { }
        Mock Read-Host -ModuleName IPAP { return 'C:\FromPrompt' }
        Mock Get-ProjectBriefInfo -ModuleName IPAP { return 'Brief text', 'TestProject' }
        Mock New-ProjectStructure -ModuleName IPAP { return $Script:ProjectDir }
        Mock New-ReadmeFile -ModuleName IPAP { }
        Mock Select-NonTextImage -ModuleName IPAP { return @() }
        Mock Copy-Item -ModuleName IPAP { }
        Mock Test-Path -ModuleName IPAP { return $true }
        Mock New-Item -ModuleName IPAP { }
        Mock Invoke-ParallelUpscale -ModuleName IPAP { return @{ SuccessCount = 0; FailedCount = 0 } }
        Mock Test-UpscaleResult -ModuleName IPAP { return $true }

        Mock Get-ImageInfo -ModuleName IPAP {
            return [PSCustomObject]@{ Images = $Script:Images; Count = $Script:Images.Count }
        }
        Mock Get-ImageLevel -ModuleName IPAP {
            param([array]$Images)
            return $Images | ForEach-Object {
                [PSCustomObject]@{
                    Image    = $PSItem
                    Level    = $Script:LevelByImage[$PSItem.Name]
                    LongEdge = 1920
                    YDIF     = 8.0
                }
            }
        }
    }

    Context 'L1 正常执行路径' {
        It '完整流程应按顺序调用各协作者' {
            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Not -Throw

            Should -Invoke -ModuleName IPAP Get-ImageInfo -Times 1 -Exactly
            Should -Invoke -ModuleName IPAP Get-ProjectBriefInfo -Times 1 -Exactly
            Should -Invoke -ModuleName IPAP New-ProjectStructure -Times 1 -Exactly
            Should -Invoke -ModuleName IPAP Select-NonTextImage -Times 1 -Exactly
            Should -Invoke -ModuleName IPAP New-ReadmeFile -Times 1 -Exactly
        }

        It '显式传 -Config 时即使模块内配置实例为空也应正常执行' {
            InModuleScope IPAP { $script:IPAPConfigInstance = $null }

            { Start-IPAPWorkflow -Config $Script:MockConfig -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } |
                Should -Not -Throw

            Should -Invoke -ModuleName IPAP Get-ProjectBriefInfo -Times 1 -Exactly
        }

        It '显式给出 BaseDir 与 SourceDir 时不应交互' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Read-Host -Times 0 -Exactly
        }

        It '正常结束时不应产生管道输出' {
            $Result = Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'L2 异常流程' {
        It '配置未初始化且未传 -Config 时应抛出 InvalidOperationException' {
            InModuleScope IPAP { $script:IPAPConfigInstance = $null }
            $Thrown = $null

            try {
                Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception | Should -BeOfType ([System.InvalidOperationException])
            $Thrown.Exception.Message | Should -BeExactly '配置未初始化，请先调用 Get-Configuration'
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
            Should -Invoke -ModuleName IPAP New-ProjectStructure -Times 0 -Exactly
        }

        It 'New-ProjectStructure 返回 $null 时应抛出项目初始化失败' {
            Mock -ModuleName IPAP New-ProjectStructure { return $null }
            $Thrown = $null

            try {
                Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.InvalidOperationException])
            $Thrown.Exception.Message | Should -BeExactly '项目初始化失败'
            # 内层记录现场 1 次 + 外层 catch 记录上下文 1 次
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' } -Times 2 -Exactly
        }

        It '复制有文字图失败时应包装为 IOException 并保留内层异常' {
            Mock -ModuleName IPAP Copy-Item { throw 'disk full' }
            $Thrown = $null

            try {
                Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.IO.IOException])
            $Thrown.Exception.Message | Should -BeLike '复制有文字图失败: *'
            $Thrown.Exception.InnerException.Message | Should -BeExactly 'disk full'
        }
    }

    Context 'L3 参数契约与边界数据' {
        It 'BaseDir 为空时应回退到配置中的基准项目目录' {
            Start-IPAPWorkflow -BaseDir '' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-ProjectStructure `
                -ParameterFilter { $BaseDir -eq 'C:\Projects' } -Times 1 -Exactly
        }

        It 'BaseDir 为纯空白时应 Trim 成空串，并在参数绑定阶段被 New-ProjectStructure 拒绝' {
            # 现状：if (-not $BaseDir) 把纯空白当作有效值，不会回退到配置；Trim 后为 ''，
            # 由 New-ProjectStructure 的 Mandatory [string] 在「参数绑定阶段」拒绝，函数体不会执行。
            # 该「参数优先级」不一致已登记至 doc/将来要改的地方.md
            $Thrown = $null

            try {
                Start-IPAPWorkflow -BaseDir "`t`n " -SourceDir 'C:\Images'
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception.GetType().FullName | Should -BeExactly 'System.Management.Automation.ParameterBindingValidationException'
            $Thrown.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationErrorEmptyStringNotAllowed*'
            $Thrown.Exception.Message | Should -BeLike '*BaseDir*'
            Should -Invoke -ModuleName IPAP New-ProjectStructure -Times 0 -Exactly
        }

        It '超长 BaseDir 应原样透传' {
            Start-IPAPWorkflow -BaseDir ('C:\' + ('a' * 250)) -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-ProjectStructure `
                -ParameterFilter { $BaseDir -eq ('C:\' + ('a' * 250)) } -Times 1 -Exactly
        }

        It '含通配符与符号的 BaseDir 应原样透传' {
            Start-IPAPWorkflow -BaseDir 'C:\Test[123]\{Special}@#$%' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-ProjectStructure `
                -ParameterFilter { $BaseDir -eq 'C:\Test[123]\{Special}@#$%' } -Times 1 -Exactly
        }

        It '含 Unicode 的 BaseDir 应原样透传' {
            Start-IPAPWorkflow -BaseDir 'C:\Test\αβγ' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-ProjectStructure `
                -ParameterFilter { $BaseDir -eq 'C:\Test\αβγ' } -Times 1 -Exactly
        }

        It 'SourceDir 为空时应回退到配置中的源图片目录' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir ''

            Should -Invoke -ModuleName IPAP Get-ImageInfo `
                -ParameterFilter { $SourceDir -eq 'C:\Images' } -Times 1 -Exactly
        }

        It '源目录没有图片时应警告并终止流程' {
            $Script:Images = @()

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -eq '源目录中没有图片，工作流终止' } -Times 1 -Exactly
            Should -Invoke -ModuleName IPAP New-ProjectStructure -Times 0 -Exactly
        }
    }

    Context 'L4 分支与循环' {
        It '未传 -Config 时应走真实守卫并取得模块内缓存的配置实例' {
            # 夹具已通过 InModuleScope 注入实例；此处不传 -Config，覆盖 Test-ConfigurationInitialized 与 Get-Configuration
            { Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images' } | Should -Not -Throw

            Should -Invoke -ModuleName IPAP Get-ProjectBriefInfo `
                -ParameterFilter { $Author -eq 'TestAuthor' } -Times 1 -Exactly
        }

        It '有文字图 Level 1 应调用 FFmpeg 引擎并输出到 02_Preprocessing' {
            $Script:LevelByImage = @{ '1.jpg' = 1; '2.jpg' = 1 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale `
                -ParameterFilter { $Engine -eq 'FFmpeg' -and $OutputDir -eq 'C:\Projects\2026-01-01_TestProject\02_Preprocessing' } `
                -Times 1 -Exactly
        }

        It '有文字图 Level 2 且 Real-CUGAN 可用时应调用 RealCugan 引擎' {
            $Script:LevelByImage = @{ '1.jpg' = 2; '2.jpg' = 2 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale `
                -ParameterFilter { $Engine -eq 'RealCugan' -and $ModelPath -eq 'models-se' } `
                -Times 1 -Exactly
        }

        It '有文字图 Level 2 且缺少 Real-CUGAN 时应警告而不处理' {
            $Config = InModuleScope IPAP -Parameters @{ Root = $Script:ConfigRoot } -ScriptBlock {
                param($Root)
                $paths = [PathConfiguration]::new($Root, 'C:\Projects', 'C:\Images')
                $tools = [ToolConfiguration]::new($paths, @{})   # 默认没有 RealCuganExePath
                $app = [ApplicationConfiguration]::new(@{})
                $app.MaxWorkers = 8
                $project = [ProjectConfiguration]::new(@{})
                [IPAPConfiguration]::new($paths, $tools, $app, $project)
            }
            $Script:LevelByImage = @{ '1.jpg' = 2; '2.jpg' = 2 }

            Start-IPAPWorkflow -Config $Config -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*未找到可执行文件*' } -Times 1 -Exactly
        }

        It '无文字图 Level 2 且 Real-CUGAN 可用时应调用 RealCugan 引擎' {
            Mock -ModuleName IPAP Select-NonTextImage { return $Script:Image2 }
            $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 2 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale `
                -ParameterFilter {
                    $Engine -eq 'RealCugan' -and
                    $OutputDir -like '*original_non_text_raw' -and
                    $ModelPath -eq 'models-se' -and
                    @($Images).Count -eq 1
                } -Times 1 -Exactly
        }

        It '无文字图 Level 2 且缺少 Real-CUGAN 时应警告而不处理' {
            $Config = InModuleScope IPAP -Parameters @{ Root = $Script:ConfigRoot } -ScriptBlock {
                param($Root)
                $paths = [PathConfiguration]::new($Root, 'C:\Projects', 'C:\Images')
                $tools = [ToolConfiguration]::new($paths, @{})
                $app = [ApplicationConfiguration]::new(@{})
                $app.MaxWorkers = 8
                $project = [ProjectConfiguration]::new(@{})
                [IPAPConfiguration]::new($paths, $tools, $app, $project)
            }
            Mock -ModuleName IPAP Select-NonTextImage { return $Script:Image2 }
            $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 2 }

            Start-IPAPWorkflow -Config $Config -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*无文字图 Level 2*未找到可执行文件*' } -Times 1 -Exactly
        }

        It '复制无文字图 Level 0 失败时应包装为 IOException 并保留内层异常' {
            Mock -ModuleName IPAP Select-NonTextImage { return $Script:Image2 }
            Mock -ModuleName IPAP Copy-Item -ParameterFilter { $Destination -like '*original_non_text_raw' } { throw 'disk full' }
            $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 0 }
            $Thrown = $null

            try {
                Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'
            }
            catch {
                $Thrown = $PSItem
            }

            $Thrown.Exception | Should -BeOfType ([System.IO.IOException])
            $Thrown.Exception.Message | Should -BeLike '复制 Level 0 无文字图失败: *'
            $Thrown.Exception.InnerException.Message | Should -BeExactly 'disk full'
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Level -eq 'Error' -and $Message -eq '复制 Level 0 无文字图失败: disk full' } -Times 1 -Exactly
        }
        It '存在无文字图时应有文字图取差集' {
            Mock -ModuleName IPAP Select-NonTextImage { return $Script:Image2 }
            $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 1 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            # 只有 1.jpg 属于有文字图，应只复制它一次
            Should -Invoke -ModuleName IPAP Copy-Item `
                -ParameterFilter { $LiteralPath -eq 'C:\src\1.jpg' } -Times 1 -Exactly
            Should -Invoke -ModuleName IPAP Copy-Item `
                -ParameterFilter { $LiteralPath -eq 'C:\src\2.jpg' } -Times 0 -Exactly
        }

        It '无文字图 Level 1 应输出到 original_non_text_raw' {
            Mock -ModuleName IPAP Select-NonTextImage { return $Script:Image2 }
            $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 1 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale `
                -ParameterFilter { $Engine -eq 'FFmpeg' -and $OutputDir -like '*original_non_text_raw' } `
                -Times 1 -Exactly
        }

        It '无文字图 Level 0 应复制到 original_non_text_raw 并补建目录' {
            Mock -ModuleName IPAP Select-NonTextImage { return $Script:Image2 }
            Mock -ModuleName IPAP Test-Path { return $false }
            $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 0 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-Item `
                -ParameterFilter { $Path -like '*original_non_text_raw' } -Times 1 -Exactly
            Should -Invoke -ModuleName IPAP Copy-Item `
                -ParameterFilter { $LiteralPath -eq 'C:\src\2.jpg' -and $Destination -like '*original_non_text_raw' } `
                -Times 1 -Exactly
        }

        It '有文字图全部为 Level 0 时不应调用高清化' {
            $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 0 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry `
                -ParameterFilter { $Message -eq '所有有文字图均为高清 (Level 0)，跳过预处理' } -Times 1 -Exactly
        }

        It 'BaseDir 与 SourceDir 在配置中也为空时应通过 Read-Host 获取' {
            $Config = InModuleScope IPAP -Parameters @{ Root = $Script:ConfigRoot } -ScriptBlock {
                param($Root)
                $paths = [PathConfiguration]::new($Root, '', '')
                $tools = [ToolConfiguration]::new($paths, @{})
                $app = [ApplicationConfiguration]::new(@{})
                $project = [ProjectConfiguration]::new(@{})
                [IPAPConfiguration]::new($paths, $tools, $app, $project)
            }

            Start-IPAPWorkflow -Config $Config

            Should -Invoke -ModuleName IPAP Read-Host -Times 2 -Exactly
            Should -Invoke -ModuleName IPAP New-ProjectStructure `
                -ParameterFilter { $BaseDir -eq 'C:\FromPrompt' } -Times 1 -Exactly
        }
    }

    Context 'L5 调用契约验证' {
        It 'New-ProjectStructure 应收到 Trim 后的 BaseDir 与项目简报中的项目名' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects  ' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-ProjectStructure `
                -ParameterFilter { $BaseDir -eq 'C:\Projects' -and $ProjectName -eq 'TestProject' } -Times 1 -Exactly
        }

        It 'Get-ProjectBriefInfo 应收到配置中的项目信息' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Get-ProjectBriefInfo `
                -ParameterFilter { $Author -eq 'TestAuthor' -and $OriginalTitle -eq 'TestTitle' -and $ChineseTitle -eq '测试标题' } `
                -Times 1 -Exactly
        }

        It 'New-ReadmeFile 应收到项目目录、数量、倍数与简报文本' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-ReadmeFile -ParameterFilter {
                $ProjectDir -eq 'C:\Projects\2026-01-01_TestProject' -and
                $ProjectName -eq 'TestProject' -and
                $ImageCount -eq 2 -and
                $UpscaleRatio -eq 2 -and
                $BriefText -eq 'Brief text'
            } -Times 1 -Exactly
        }

        It 'New-ReadmeFile 的 -NeedUpscale 与 Level 数组应反映分级结果' {
            $Script:LevelByImage = @{ '1.jpg' = 1; '2.jpg' = 1 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-ReadmeFile -ParameterFilter {
                [bool]$NeedUpscale -eq $true -and
                @($Level1ImageLevels).Count -eq 2 -and
                @($Level2ImageLevels).Count -eq 0
            } -Times 1 -Exactly
        }

        It 'New-ReadmeFile 在全部 Level 0 时 -NeedUpscale 应为 false' {
            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP New-ReadmeFile -ParameterFilter {
                [bool]$NeedUpscale -eq $false -and
                @($Level1ImageLevels).Count -eq 0 -and
                @($Level2ImageLevels).Count -eq 0
            } -Times 1 -Exactly
        }

        It 'Invoke-ParallelUpscale 的 -MaxWorkers 应来自配置' {
            $Script:LevelByImage = @{ '1.jpg' = 1; '2.jpg' = 1 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale `
                -ParameterFilter { $MaxWorkers -eq 8 } -Times 1 -Exactly
        }

        It 'Invoke-ParallelUpscale 的 -Images 应是无文字图子集' {
            Mock -ModuleName IPAP Select-NonTextImage { return $Script:Image2 }
            $Script:LevelByImage = @{ '1.jpg' = 0; '2.jpg' = 1 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Invoke-ParallelUpscale -ParameterFilter {
                @($Images).Count -eq 1 -and @($Images)[0].Name -eq '2.jpg'
            } -Times 1 -Exactly
        }

        It 'Test-UpscaleResult 的 -ExpectedCount 应等于 Level 1 与 Level 2 之和' {
            $Script:LevelByImage = @{ '1.jpg' = 1; '2.jpg' = 1 }

            Start-IPAPWorkflow -BaseDir 'C:\Projects' -SourceDir 'C:\Images'

            Should -Invoke -ModuleName IPAP Test-UpscaleResult `
                -ParameterFilter { $ExpectedCount -eq 2 } -Times 1 -Exactly
        }
    }
}
