#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Confirm-ProjectConfiguration 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 覆盖 Confirm-ProjectConfiguration：
    L1 正常流程、L2 非交互与异常流程、L3 边界输入、
    L4 分支与递归、L5 输出对象字段。
    夹具（§7.2 / §7.7）：BeforeEach 在模块作用域构造完整 IPAPConfiguration
    （ProjectRoot 指向 TestDrive 真实目录），AfterEach 清理；
    交互命令 Read-Host / Read-MultiLineInput 全部 Mock，不触碰真实控制台。
#>

Describe 'Confirm-ProjectConfiguration Unit Tests' -Tag 'Confirm-ProjectConfiguration', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 统一设置每例的模块作用域输入状态
        function Set-ConfirmTestState {
            [CmdletBinding()]
            param(
                [string[]]$ReadHostResponses = @(),
                [string[]]$OriginalOverviewLines = @(),
                [string[]]$ChineseOverviewLines = @(),
                [switch]$EditorReload
            )
            InModuleScope IPAP -Parameters @{
                Responses      = $ReadHostResponses
                OriginalLines  = $OriginalOverviewLines
                ChineseLines   = $ChineseOverviewLines
                UseReloaded    = [bool]$EditorReload
            } -ScriptBlock {
                param($Responses, $OriginalLines, $ChineseLines, $UseReloaded)

                $script:ReadHostQueue.Clear()
                foreach ($response in $Responses) { $script:ReadHostQueue.Enqueue($response) }
                $script:OriginalOverviewLines = $OriginalLines
                $script:ChineseOverviewLines = $ChineseLines
                $script:GetConfigurationResult = $UseReloaded ? $script:ReloadedConfig : $script:TestConfig
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 共享夹具：TestDrive 项目根目录
        $script:ConfigRoot = Join-Path $TestDrive 'ConfigRoot'
        New-Item -Path $script:ConfigRoot -ItemType Directory -Force | Out-Null

        InModuleScope IPAP -Parameters @{ Root = $script:ConfigRoot } -ScriptBlock {
            param($Root)

            # 外部命令：工具路径解析保持确定性
            Mock -CommandName Get-Command -ModuleName IPAP { return $null }
            Mock -CommandName Write-LogEntry -ModuleName IPAP { }
            Mock -CommandName Start-Process -ModuleName IPAP { }
            Mock -CommandName Reset-Configuration -ModuleName IPAP { }
            Mock -CommandName Get-Configuration -ModuleName IPAP { return $script:GetConfigurationResult }

            # 交互命令：Read-Host 用队列驱动，多行输入按 Prompt 返回行数组
            Mock -CommandName Read-Host -ModuleName IPAP {
                if ($script:ReadHostQueue.Count -gt 0) { return $script:ReadHostQueue.Dequeue() }
                return $null
            }
            Mock -CommandName Read-MultiLineInput -ModuleName IPAP {
                param($Prompt)
                if ($Prompt -like '*原文*') { return $script:OriginalOverviewLines }
                if ($Prompt -like '*中文*') { return $script:ChineseOverviewLines }
                return @()
            }

            # 每例复位的可变状态
            $script:ReadHostQueue = [System.Collections.Generic.Queue[string]]::new()
            $script:OriginalOverviewLines = @()
            $script:ChineseOverviewLines = @()
            $script:ExpectedProjectRoot = $Root

            # 构造完整配置：路径、项目、应用字段均可预测
            $paths = [PathConfiguration]::new($Root, 'D:\base', 'D:\source')
            $tools = [ToolConfiguration]::new($paths, @{ paths = @{} })
            $app = [ApplicationConfiguration]::new(@{
                    app_settings = @{
                        max_workers             = 4
                        model_select            = 'models-pro'
                        supported_image_formats = @('.png')
                        upscale_timeout_sec     = 120
                    }
                    upscale      = @{ upscale_ratio = 4; noise_level = 2 }
                    webp         = @{ enabled = $false; lossless = $false; quality = 80 }
                })
            $project = [ProjectConfiguration]::new(@{
                    project = @{
                        author            = '鲁迅'
                        original_title    = '呐喊'
                        chinese_title     = '呐喊'
                        original_overview = '原文简介'
                        chinese_overview  = '中文简介'
                    }
                })
            $script:TestConfig = [IPAPConfiguration]::new($paths, $tools, $app, $project)
            # 编辑器重载后的新实例：外壳引用不同，字段与 TestConfig 一致
            $script:ReloadedConfig = [IPAPConfiguration]::new($paths, $tools, $app, $project)
            $script:GetConfigurationResult = $script:TestConfig
        }
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:ConfigRoot) {
            Remove-Item -LiteralPath $script:ConfigRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'L1 正常流程' {
        It 'Y 时应返回当前配置并记录应用日志' {
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:TestConfig
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -eq '应用当前配置' } -Times 1 -Exactly
                Should -Invoke -CommandName Read-Host -Times 1 -Exactly
            }
        }

        It 'y 时应返回当前配置' {
            Set-ConfirmTestState -ReadHostResponses @('y')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:TestConfig
                Should -Invoke -CommandName Start-Process -Times 0 -Exactly
            }
        }

        It '传入 Config 时不应调用 Get-Configuration' {
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP {
                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Get-Configuration -Times 0 -Exactly
            }
        }

        It '预览应输出三个分区标题与已配置回退' {
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP {
                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -eq '【路径配置】' } -Times 1 -Exactly
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -eq '【项目信息】' } -Times 1 -Exactly
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -eq '【应用配置】' } -Times 1 -Exactly
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -eq '  基准项目目录: D:\base' } -Times 1 -Exactly
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -eq '  源图片目录: D:\source' } -Times 1 -Exactly
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -eq '  原文简介: 已配置' } -Times 1 -Exactly
            }
        }
    }

    Context 'L2 非交互与异常流程' {
        It 'Y/N 未读到输入时应返回当前配置且不进入修改菜单' {
            Set-ConfirmTestState -ReadHostResponses @()
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:TestConfig
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*未读到输入*' } -Times 1 -Exactly
                Should -Invoke -CommandName Read-Host -Times 1 -Exactly
            }
        }

        It '1/2 未读到输入时应返回当前配置且不打开编辑器' {
            Set-ConfirmTestState -ReadHostResponses @('N')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:TestConfig
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -like '*未读到输入*' } -Times 1 -Exactly
                Should -Invoke -CommandName Start-Process -Times 0 -Exactly
                Should -Invoke -CommandName Reset-Configuration -Times 0 -Exactly
            }
        }

        It '未传入 Config 时应调用 Get-Configuration' {
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration

                $result | Should -Be $script:TestConfig
                Should -Invoke -CommandName Get-Configuration -Times 1 -Exactly
            }
        }

        It 'Get-Configuration 抛逻辑异常时应向上传播' {
            InModuleScope IPAP {
                Mock -CommandName Get-Configuration -ModuleName IPAP {
                    throw [System.InvalidOperationException]::new('配置未初始化')
                }

                { Confirm-ProjectConfiguration } |
                    Should -Throw -ExceptionType ([System.InvalidOperationException]) -ExpectedMessage '配置未初始化'
            }
        }
    }

    Context 'L3 边界输入' {
        It 'Y/N 输入非 Y 时应视为不应用并进入修改菜单' {
            Set-ConfirmTestState -ReadHostResponses @('x', '2', '', '', '', '')
            InModuleScope IPAP {
                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -like '*您选择不应用当前配置*' } -Times 1 -Exactly
                Should -Invoke -CommandName Start-Process -Times 0 -Exactly
            }
        }

        It '修改方式输入非 1 时应按控制台输入处理' {
            Set-ConfirmTestState -ReadHostResponses @('N', '3', '', '', '', '')
            InModuleScope IPAP {
                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -like '*请在控制台输入配置信息*' } -Times 1 -Exactly
                Should -Invoke -CommandName Start-Process -Times 0 -Exactly
            }
        }

        It '控制台输入全为空时应保持原值返回' {
            Set-ConfirmTestState -ReadHostResponses @('N', '2', '', '', '', '')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:TestConfig
                $result.Paths.SourceDir | Should -Be 'D:\source'
                $result.Project.Author | Should -Be '鲁迅'
                $result.Project.OriginalTitle | Should -Be '呐喊'
                $result.Project.ChineseTitle | Should -Be '呐喊'
                $result.Project.OriginalOverview | Should -Be '原文简介'
                $result.Project.ChineseOverview | Should -Be '中文简介'
            }
        }

        It '控制台输入只修改部分字段时应只更新这些字段' {
            Set-ConfirmTestState -ReadHostResponses @('N', '2', 'D:\new-source', '新作者', '', '', 'Y')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result.Paths.SourceDir | Should -Be 'D:\new-source'
                $result.Project.Author | Should -Be '新作者'
                $result.Project.OriginalTitle | Should -Be '呐喊'
                $result.Project.ChineseTitle | Should -Be '呐喊'
                $result.Project.OriginalOverview | Should -Be '原文简介'
                $result.Project.ChineseOverview | Should -Be '中文简介'
            }
        }
    }

    Context 'L4 分支与递归' {
        It '选择编辑器时应打开配置、重置并重新加载后递归确认' {
            Set-ConfirmTestState -ReadHostResponses @('N', '1', '', 'Y') -EditorReload
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:ReloadedConfig
                Should -Invoke -CommandName Start-Process -Times 1 -Exactly -ParameterFilter {
                    $FilePath -eq $script:TestConfig.Paths.ConfigPath
                }
                Should -Invoke -CommandName Reset-Configuration -Times 1 -Exactly
                Should -Invoke -CommandName Get-Configuration -Times 1 -Exactly -ParameterFilter {
                    $ProjectRoot -eq $script:ExpectedProjectRoot
                }
                Should -Invoke -CommandName Read-Host -Times 4 -Exactly
            }
        }

        It 'Start-Process 抛异常时应记录警告并继续重置流程' {
            Set-ConfirmTestState -ReadHostResponses @('N', '1', '', 'Y') -EditorReload
            InModuleScope IPAP {
                Mock -CommandName Start-Process -ModuleName IPAP {
                    throw [System.InvalidOperationException]::new('无法打开')
                }

                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:ReloadedConfig
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -like '*无法自动打开配置文件*' } -Times 1 -Exactly
                Should -Invoke -CommandName Reset-Configuration -Times 1 -Exactly
            }
        }

        It '控制台修改后应递归确认一次并返回修改后的配置' {
            Set-ConfirmTestState -ReadHostResponses @('N', '2', 'D:\new-source', '', '', '', 'Y')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:TestConfig
                $result.Paths.SourceDir | Should -Be 'D:\new-source'
                # 初次 Y/N + 选择 + 4 个字段 + 递归 Y/N = 7 次
                Should -Invoke -CommandName Read-Host -Times 7 -Exactly
                Should -Invoke -CommandName Start-Process -Times 0 -Exactly
                Should -Invoke -CommandName Reset-Configuration -Times 0 -Exactly
            }
        }

        It '控制台无改动时递归确认读到 EOF 应返回原配置' {
            Set-ConfirmTestState -ReadHostResponses @('N', '2', '', '', '', '')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                $result | Should -Be $script:TestConfig
                # 初次 Y/N + 选择 + 4 个字段 + 递归 Y/N（EOF）= 7 次
                Should -Invoke -CommandName Read-Host -Times 7 -Exactly
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter { $Message -like '*未读到输入*' } -Times 1 -Exactly
            }
        }
    }

    Context 'L4 源目录体检' {
        It '源目录不存在时应记录 Error 提示' {
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP -Parameters @{ Missing = (Join-Path $TestDrive 'no-such-src') } -ScriptBlock {
                param($Missing)
                $script:TestConfig.Paths.SourceDir = $Missing

                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Write-LogEntry -Times 1 -Exactly `
                    -ParameterFilter { $Level -eq 'Error' -and $Message -like '*源图片目录不存在*' }
            }
        }

        It '源目录存在但没有图片时应记录 Warning 并给出支持的格式' {
            $EmptyDir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'empty-src') -Force
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP -Parameters @{ Dir = $EmptyDir.FullName } -ScriptBlock {
                param($Dir)
                $script:TestConfig.Paths.SourceDir = $Dir

                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Write-LogEntry -Times 1 -Exactly `
                    -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*没有图片文件*' -and $Message -like '*.png*' }
            }
        }

        It '源目录有支持格式的图片时应记录 Success 与数量' {
            $ImageDir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'with-img') -Force
            1..2 | ForEach-Object { New-Item -ItemType File -Path (Join-Path $ImageDir.FullName "$_.png") -Force | Out-Null }
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP -Parameters @{ Dir = $ImageDir.FullName } -ScriptBlock {
                param($Dir)
                $script:TestConfig.Paths.SourceDir = $Dir

                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Write-LogEntry -Times 1 -Exactly `
                    -ParameterFilter { $Level -eq 'Success' -and $Message -like '*检测到 2 张图片*' }
            }
        }

        It '源目录未配置时不应做体检' {
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP {
                $script:TestConfig.Paths.SourceDir = ''

                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Write-LogEntry -Times 0 -Exactly `
                    -ParameterFilter { $Message -like '*源图片目录不存在*' -or $Message -like '*没有图片文件*' }
            }
        }
    }

    Context 'L5 输出字段验证' {
        It '控制台修改全部字段时应逐字段更新且不影响其余字段' {
            Set-ConfirmTestState `
                -ReadHostResponses @('N', '2', 'D:\new-source', '新作者', '新作品', '新译名', 'Y') `
                -OriginalOverviewLines @('原文第一行', '原文第二行') `
                -ChineseOverviewLines @('中文第一行', '中文第二行')
            InModuleScope IPAP {
                $result = Confirm-ProjectConfiguration -Config $script:TestConfig

                # 被修改的 6 个字段
                $result.Paths.SourceDir | Should -Be 'D:\new-source'
                $result.Project.Author | Should -Be '新作者'
                $result.Project.OriginalTitle | Should -Be '新作品'
                $result.Project.ChineseTitle | Should -Be '新译名'
                $result.Project.OriginalOverview | Should -Be "原文第一行`n原文第二行"
                $result.Project.ChineseOverview | Should -Be "中文第一行`n中文第二行"

                # 未被修改的字段
                $result.Paths.ProjectRoot | Should -Be $script:TestConfig.Paths.ProjectRoot
                $result.Paths.BaseProjectDir | Should -Be 'D:\base'
                $result.Paths.ConfigPath | Should -Be $script:TestConfig.Paths.ConfigPath
                $result.App.MaxWorkers | Should -Be 4
                $result.App.UpscaleRatio | Should -Be 4
                $result.App.ModelSelect | Should -Be 'models-pro'
            }
        }
    }

    Context 'L5 预览显示' {
        It '中文简介应全文显示而不是只显示「已配置」' {
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP {
                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                # 标题行带字数
                Should -Invoke -CommandName Write-LogEntry -Times 1 -Exactly `
                    -ParameterFilter { $Message -eq '  中文简介（共 4 字）:' }
                # 正文单独一条日志
                Should -Invoke -CommandName Write-LogEntry -Times 1 -Exactly `
                    -ParameterFilter { $Message -eq '中文简介' }
                # 旧写法「已配置」不应再出现
                Should -Invoke -CommandName Write-LogEntry -Times 0 -Exactly `
                    -ParameterFilter { $Message -eq '  中文简介: 已配置' }
            }
        }

        It '中文简介为空时应显示未配置' {
            Set-ConfirmTestState -ReadHostResponses @('Y')
            InModuleScope IPAP {
                $script:TestConfig.Project.ChineseOverview = ''
                $null = Confirm-ProjectConfiguration -Config $script:TestConfig

                Should -Invoke -CommandName Write-LogEntry -Times 1 -Exactly `
                    -ParameterFilter { $Message -eq '  中文简介: [未配置]' }
            }
        }
    }
}
