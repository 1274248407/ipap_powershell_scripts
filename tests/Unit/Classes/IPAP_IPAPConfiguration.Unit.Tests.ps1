#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - IPAPConfiguration 单元测试
.DESCRIPTION
    测试 IPAPConfiguration 聚合类的构造函数、静态 Load 方法、
    ReadConfigFile（TOML 读取与 Windows 路径转义修复）和 MergeSettings（浅合并逻辑）。
    按 docs/单元测试方法论.md 的 L1-L5 覆盖：
    - L1 正常流程：四子配置聚合、TOML 解析与合并、ReadConfigFile 读取
    - L2 异常流程：TOML 解析失败、转义修复失败、配置块类型非法
    - L3 边界数据：配置文件缺失 / 空文件、PSToml 不可用、多种配置组合
    - L4 分支覆盖：候选 PSToml 导入成功 / 失败、转义修复重试、OrderedDictionary 转换
    - L5 输出字段：子配置类型、实例独立性
    共享夹具（§7.2）：BeforeEach 统一创建 MockProject 目录与 0 字节 config.toml，AfterEach 清理；
    模块内依赖统一在 BeforeEach 用 -ModuleName IPAP Mock（§7.5），各用例只覆盖自己的差异。
    ReadConfigFile 与 MergeSettings 是模块内的隐藏静态方法，在 InModuleScope 中可直接调用，无需反射。
#>

Describe 'IPAPConfiguration Unit Tests' -Tag 'IPAPConfiguration', 'IPAP', 'Classes' {
    BeforeAll {
        # tests\Unit\Classes → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 真实 TOML 解析用例依赖 PSToml：按「构建产物 → 全局已装」顺序探测导入
        # （Get-Command/ConvertFrom-Toml 的 Mock 用例优先走 Mock，不受此导入影响）
        $script:PSTomlAvailable = $false
        foreach ($PSTomlPath in @(
                (Join-Path $script:ProjectRoot 'output\RequiredModules\PSToml\0.5.0'),
                'PSToml'
            )) {
            try {
                Import-Module $PSTomlPath -Force -Global -ErrorAction Stop
                $script:PSTomlAvailable = $true
                break
            }
            catch { }
        }
        
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
        Remove-Module 'PSToml' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 共享夹具（§7.2）：项目目录 + 0 字节 config.toml；「配置文件不存在」组会在自己的 BeforeEach 中删掉它
        $script:TestProjectDir = Join-Path $TestDrive 'MockProject'
        New-Item -Path $script:TestProjectDir -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $script:TestProjectDir 'config.toml') -ItemType File -Force | Out-Null

        # 模块内依赖统一在此 Mock（§7.5）：-ModuleName 指定注入到 IPAP 模块作用域
        Mock -CommandName Write-LogEntry -ModuleName IPAP { }
        Mock -CommandName Import-Module -ModuleName IPAP { }
        # 默认视为「文件有内容且可解析」，各用例按需覆盖为具体 TOML 或空字符串
        Mock -CommandName Get-Content -ModuleName IPAP {
            return '# 占位内容，解析结果由 ConvertFrom-Toml 的 Mock 决定'
        }
        # 默认视为「ConvertFrom-Toml 可用、其余命令缺席」；需要「PSToml 不可用」的组在 Context 级覆盖
        Mock -CommandName Get-Command -ModuleName IPAP {
            param($Name)
            if ($Name -eq 'ConvertFrom-Toml') {
                return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
            }
            return $null
        }
    }

    AfterEach {
        # 清理本用例产生的临时目录（§7.7）；$TestDrive 由 Pester 兜底清空
        if (Test-Path -LiteralPath $script:TestProjectDir) {
            Remove-Item -LiteralPath $script:TestProjectDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context '构造函数 - 正常路径（L1）' {
        It '应正确聚合四个子配置对象' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $toolConfig = [ToolConfiguration]::new($pathConfig, @{ paths = @{} })
                $appConfig = [ApplicationConfiguration]::new(@{})
                $projectConfig = [ProjectConfiguration]::new(@{})

                $config = [IPAPConfiguration]::new($pathConfig, $toolConfig, $appConfig, $projectConfig)

                $config.Paths | Should -Be $pathConfig
                $config.Tools | Should -Be $toolConfig
                $config.App | Should -Be $appConfig
                $config.Project | Should -Be $projectConfig
            }
        }

        It '每个子配置应为正确的类型' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $toolConfig = [ToolConfiguration]::new($pathConfig, @{ paths = @{} })
                $appConfig = [ApplicationConfiguration]::new(@{})
                $projectConfig = [ProjectConfiguration]::new(@{})

                $config = [IPAPConfiguration]::new($pathConfig, $toolConfig, $appConfig, $projectConfig)

                $config.Paths | Should -BeOfType 'PathConfiguration'
                $config.Tools | Should -BeOfType 'ToolConfiguration'
                $config.App | Should -BeOfType 'ApplicationConfiguration'
                $config.Project | Should -BeOfType 'ProjectConfiguration'
            }
        }
    }

    Context '静态方法 Load - 配置文件不存在（L3）' {
        BeforeEach {
            # 本组验证「无配置文件」分支，移除默认夹具中的 config.toml
            Remove-Item -LiteralPath (Join-Path $script:TestProjectDir 'config.toml') -Force
        }

        It 'config.toml 不存在时应使用默认配置创建实例' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $config = [IPAPConfiguration]::Load($p)

                # 类型契约：-BeOfType 兼作非空校验
                $config | Should -BeOfType 'IPAPConfiguration'
                # 聚合契约：四个子配置引用须为正确类型，各自默认值由对应的 It 全量断言
                $config.Paths | Should -BeOfType 'PathConfiguration'
                $config.Tools | Should -BeOfType 'ToolConfiguration'
                $config.App | Should -BeOfType 'ApplicationConfiguration'
                $config.Project | Should -BeOfType 'ProjectConfiguration'
            }
        }

        It 'config.toml 不存在时应记录 Info 日志' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                [IPAPConfiguration]::Load($p) | Out-Null

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter {
                    $Level -eq 'Info' -and $Message -like '*配置文件不存在*'
                }
            }
        }

        It 'config.toml 不存在时应使用默认 app_settings' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $config = [IPAPConfiguration]::Load($p)

                $config.App.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                # 判别锚点：默认表给 8，ApplicationConfiguration 兜底给 ProcessorCount/2
                $config.App.MaxWorkers | Should -Be 8
                $config.App.UpscaleTimeoutSec | Should -Be 3600
                $config.App.ModelSelect | Should -Be 'models-se'
            }
        }

        It 'config.toml 不存在时应使用默认 upscale 与 webp 配置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $config = [IPAPConfiguration]::Load($p)

                $config.App.UpscaleRatio | Should -Be 2
                $config.App.NoiseLevel | Should -Be 0
                $config.App.WebpEnabled | Should -Be $true
                $config.App.WebpLossless | Should -Be $true
                $config.App.WebpQuality | Should -Be 100
            }
        }

        It 'config.toml 不存在时 Project 配置应为默认值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $config = [IPAPConfiguration]::Load($p)

                $config.Project.Author | Should -Be ''
                $config.Project.OriginalTitle | Should -Be ''
                $config.Project.ChineseTitle | Should -Be ''
                $config.Project.OriginalOverview | Should -Be ''
                $config.Project.ChineseOverview | Should -Be ''
            }
        }

        It 'config.toml 不存在时路径与工具配置应为默认值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # Get-Command 对 ffmpeg 等工具命令默认返回 $null，PATH 回退分支必然落空
                $config = [IPAPConfiguration]::Load($p)

                $config.Paths.ProjectRoot | Should -Be $p
                $config.Paths.BaseProjectDir | Should -Be ''
                $config.Paths.SourceDir | Should -Be ''
                $config.Paths.BinPath | Should -Be (Join-Path $p 'bin')
                $config.Paths.ConfigPath | Should -Be (Join-Path $p 'config.toml')
                $config.Tools.FfmpegExePath | Should -BeNullOrEmpty
                $config.Tools.FfprobeExePath | Should -BeNullOrEmpty
                $config.Tools.RealCuganExePath | Should -BeNullOrEmpty
            }
        }

        It 'config.toml 不存在时默认配置的 19 个键应全部取约定默认值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 直接调用隐藏静态方法读取文件不存在分支返回的默认配置表
                $rawSettings = [IPAPConfiguration]::ReadConfigFile($p)

                # 键集合断言：5 个区块，键数总计 5 + 5 + 4 + 2 + 3 = 19，同时守住「不多不少」
                @($rawSettings.Keys | Sort-Object) | Should -Be @('app_settings', 'paths', 'project', 'upscale', 'webp')
                @($rawSettings['paths'].Keys | Sort-Object) | Should -Be @('base_project_dir', 'ffmpeg_exe', 'ffprobe_exe', 'realcugan_exe', 'source_dir')
                @($rawSettings['project'].Keys | Sort-Object) | Should -Be @('author', 'chinese_overview', 'chinese_title', 'original_overview', 'original_title')
                @($rawSettings['app_settings'].Keys | Sort-Object) | Should -Be @('max_workers', 'model_select', 'supported_image_formats', 'upscale_timeout_sec')
                @($rawSettings['upscale'].Keys | Sort-Object) | Should -Be @('noise_level', 'upscale_ratio')
                @($rawSettings['webp'].Keys | Sort-Object) | Should -Be @('enabled', 'lossless', 'quality')

                # 值断言：逐键对应源码中的默认表，是全文件默认值的唯一真源
                # 注意：键名断言只能守住键集合，键增删之外的「默认值被改动」全靠下面 19 行拦截
                $rawSettings['paths']['base_project_dir'] | Should -Be ''
                $rawSettings['paths']['source_dir'] | Should -Be ''
                $rawSettings['paths']['ffmpeg_exe'] | Should -Be ''
                $rawSettings['paths']['ffprobe_exe'] | Should -Be ''
                $rawSettings['paths']['realcugan_exe'] | Should -Be ''
                $rawSettings['project']['author'] | Should -Be ''
                $rawSettings['project']['original_title'] | Should -Be ''
                $rawSettings['project']['chinese_title'] | Should -Be ''
                $rawSettings['project']['original_overview'] | Should -Be ''
                $rawSettings['project']['chinese_overview'] | Should -Be ''
                $rawSettings['app_settings']['supported_image_formats'] | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $rawSettings['app_settings']['max_workers'] | Should -Be 8
                $rawSettings['app_settings']['upscale_timeout_sec'] | Should -Be 3600
                $rawSettings['app_settings']['model_select'] | Should -Be 'models-se'
                $rawSettings['upscale']['upscale_ratio'] | Should -Be 2
                $rawSettings['upscale']['noise_level'] | Should -Be 0
                $rawSettings['webp']['enabled'] | Should -Be $true
                $rawSettings['webp']['lossless'] | Should -Be $true
                $rawSettings['webp']['quality'] | Should -Be 100
            }
        }
    }

    Context '静态方法 Load - PSToml 模块未找到（L3）' {
        BeforeEach {
            # 本组聚焦「PSToml 不可用」路径，覆盖默认的「ConvertFrom-Toml 可用」探测
            Mock -CommandName Get-Command -ModuleName IPAP { return $null }
        }

        It 'PSToml 不可用时应使用默认配置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 该分支与「配置文件不存在」分支返回源码中同一张 $defaultSettings，故此处按原始表断言
                $rawSettings = [IPAPConfiguration]::ReadConfigFile($p)

                # 5 个区块，键集合总计 5 + 5 + 4 + 2 + 3 = 19 个
                @($rawSettings.Keys | Sort-Object) | Should -Be @('app_settings', 'paths', 'project', 'upscale', 'webp')
                @($rawSettings['paths'].Keys | Sort-Object) | Should -Be @('base_project_dir', 'ffmpeg_exe', 'ffprobe_exe', 'realcugan_exe', 'source_dir')
                @($rawSettings['project'].Keys | Sort-Object) | Should -Be @('author', 'chinese_overview', 'chinese_title', 'original_overview', 'original_title')
                @($rawSettings['app_settings'].Keys | Sort-Object) | Should -Be @('max_workers', 'model_select', 'supported_image_formats', 'upscale_timeout_sec')
                @($rawSettings['upscale'].Keys | Sort-Object) | Should -Be @('noise_level', 'upscale_ratio')
                @($rawSettings['webp'].Keys | Sort-Object) | Should -Be @('enabled', 'lossless', 'quality')
                # 值断言：max_workers 是默认表中唯一与类内兜底取值不同的键，恒定可证伪
                $rawSettings['app_settings']['max_workers'] | Should -Be 8

                $config = [IPAPConfiguration]::Load($p)

                # 端到端锚点：默认表给 8，ApplicationConfiguration 兜底给 ProcessorCount/2
                # （16/17 逻辑核宿主上兜底值恰好也是 8，该行届时失去鉴别力，故上面另设表层值断言）
                $config.App.MaxWorkers | Should -Be 8
            }
        }

        It 'PSToml 不可用时应记录 Info 日志' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                [IPAPConfiguration]::Load($p) | Out-Null

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter {
                    $Level -eq 'Info' -and $Message -like '*PSToml 模块未找到*'
                }
            }
        }
    }

    Context '静态方法 Load - PSToml 候选路径导入（L4）' {
        BeforeEach {
            # 本组聚焦「候选导入」分支，探测保持不可用以免后续真的走解析
            Mock -CommandName Get-Command -ModuleName IPAP { return $null }
        }

        It '候选 PSToml 目录存在时应导入该路径' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                # 造一个「存在」的候选目录；Import-Module 被 Mock，不会真的去导入空目录
                New-Item -Path (Join-Path $p 'RequiredModules\PSToml') -ItemType Directory -Force | Out-Null

                [IPAPConfiguration]::Load($p) | Out-Null

                Should -Invoke -CommandName Import-Module `
                    -ParameterFilter { $Name -like '*RequiredModules\PSToml' } -Times 1 -Exactly
            }
        }

        It '候选 PSToml 导入失败时应记录 Warning 并继续' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path (Join-Path $p 'RequiredModules\PSToml') -ItemType Directory -Force | Out-Null

                Mock -CommandName Import-Module -ModuleName IPAP { throw 'not a module' }

                $config = [IPAPConfiguration]::Load($p)

                # 导入失败不应中断流程：继续走「PSToml 未找到」→ 默认配置
                $config.App.MaxWorkers | Should -Be 8
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter {
                    $Level -eq 'Warning' -and $Message -like '*PSToml 模块导入失败*'
                }
            }
        }
    }

    Context '静态方法 Load - 空配置文件（L3）' {
        It 'config.toml 为空文件时应回退默认配置并记录 Info 日志' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 夹具中的 config.toml 是 0 字节；显式返回空字符串，命中空内容守卫
                Mock -CommandName Get-Content -ModuleName IPAP { return '' }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.MaxWorkers | Should -Be 8
                $config.App.ModelSelect | Should -Be 'models-se'
                Should -Invoke -CommandName Write-LogEntry -ParameterFilter {
                    $Level -eq 'Info' -and $Message -like '*配置文件为空*'
                }
            }
        }
    }

    Context '静态方法 Load - TOML 解析成功（L1）' {
        It '应正确解析并合并用户配置' {
            if (-not $script:PSTomlAvailable) {
                Set-ItResult -Skipped -Because 'PSToml 模块不可用'
                return
            }
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 真实 TOML：双引号内无 Windows 路径，无需转义；ConvertFrom-Toml 不做 Mock，走真实解析
                Mock -CommandName Get-Content -ModuleName IPAP { return @'
[app_settings]
model_select = "models-pro"
'@ }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.ModelSelect | Should -Be 'models-pro'
                $config.App.UpscaleTimeoutSec | Should -Be 3600
                # 判别锚点：用户未设 max_workers，此处为 8 才能证明合并后默认表确实流入，而非类内兜底
                $config.App.MaxWorkers | Should -Be 8
            }
        }

        It '路径配置中的 base_project_dir 和 source_dir 应正确透传' {
            if (-not $script:PSTomlAvailable) {
                Set-ItResult -Skipped -Because 'PSToml 模块不可用'
                return
            }
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 真实 TOML：路径中不含反斜杠，无需转义；ConvertFrom-Toml 不做 Mock，走真实解析
                Mock -CommandName Get-Content -ModuleName IPAP { return @'
[paths]
base_project_dir = "D:/documents/translation/01_Projects_Active"
source_dir = "D:/images"
'@ }

                $config = [IPAPConfiguration]::Load($p)

                $config.Paths.BaseProjectDir | Should -Be 'D:/documents/translation/01_Projects_Active'
                $config.Paths.SourceDir | Should -Be 'D:/images'
            }
        }
    }

    Context '静态方法 Load - TOML 解析失败（L2）' {
        It '解析失败且非转义问题时应抛出 InvalidOperationException 且不触发修复重试' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP {
                    throw [System.Exception]::new('Unexpected token')
                }

                { [IPAPConfiguration]::Load($p) } | Should -Throw -ExceptionType ([System.InvalidOperationException]) -ExpectedMessage '无法解析 config.toml: Unexpected token'
                # 错误消息不含转义关键字，不应进入自动修复分支，解析只被尝试一次
                Should -Invoke -CommandName ConvertFrom-Toml -Times 1 -Exactly
            }
        }
    }

    Context '静态方法 Load - Windows 路径转义自动修复（L2/L4）' {
        It '检测到反斜杠转义问题时应尝试自动修复' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $script:tomlCallCount = 0
                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP {
                    $script:tomlCallCount++
                    if ($script:tomlCallCount -eq 1) {
                        throw [System.Exception]::new('Unexpected escape character in string')
                    }
                    return @{ paths = @{ source_dir = 'C:\Users\test\images' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.Paths.SourceDir | Should -Be 'C:\Users\test\images'
            }
        }

        It '转义修复成功后应记录 Warning 日志' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $script:tomlCallCount = 0
                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP {
                    $script:tomlCallCount++
                    if ($script:tomlCallCount -eq 1) {
                        throw [System.Exception]::new('Unexpected escape character')
                    }
                    return @{ paths = @{ source_dir = 'C:\test' } }
                }

                [IPAPConfiguration]::Load($p) | Out-Null

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter {
                    $Level -eq 'Warning' -and $Message -like '*自动修复成功*'
                }
            }
        }

        It '转义修复后仍解析失败时应抛出带排查提示的 InvalidOperationException' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 自动修复会重新读取原始内容，因此需返回真实可修复的文本
                Mock -CommandName Get-Content -ModuleName IPAP { return 'source_dir = "C:\images"' }

                $script:tomlCallCount = 0
                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP {
                    $script:tomlCallCount++
                    if ($script:tomlCallCount -eq 1) {
                        throw [System.Exception]::new('Unexpected escape character in string')
                    }
                    throw [System.Exception]::new('仍含非法转义')
                }

                { [IPAPConfiguration]::Load($p) } | Should -Throw -ExceptionType ([System.InvalidOperationException]) -ExpectedMessage '无法解析 config.toml: Unexpected escape character in string。常见原因：Windows 路径使用了双引号但未正确转义反斜杠。请将路径改为单引号字面量字符串，例如 source_dir = ''C:\\path\\to\\dir'''
                # 首次解析失败后进入修复分支并重新解析，故解析共被调用两次
                Should -Invoke -CommandName ConvertFrom-Toml -Times 2 -Exactly
            }
        }

        It '真实解析：含未转义反斜杠的 Windows 路径应被自动修复并返回正确对象' {
            if (-not $script:PSTomlAvailable) {
                Set-ItResult -Skipped -Because 'PSToml 模块不可用'
                return
            }
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 真实坏 TOML：双引号内单反斜杠未转义，真实 ConvertFrom-Toml 必然抛 Unexpected escape character
                # ConvertFrom-Toml 不做 Mock，修复链路由真实解析器完整走通
                Mock -CommandName Get-Content -ModuleName IPAP { return @'
[paths]
source_dir = "C:\Users\test\images"
[app_settings]
model_select = "models-pro"
'@ }

                $config = [IPAPConfiguration]::Load($p)

                # 核心：修复后路径值正确（真实解析器背书，而非 Mock 直给）
                $config.Paths.SourceDir | Should -Be 'C:\Users\test\images'
                # 未被污染：修复未破坏其他区块的值
                $config.App.ModelSelect | Should -Be 'models-pro'
                # 判别锚点：未设 max_workers 时应为默认表 8，证明修复与合并链路无副作用
                $config.App.MaxWorkers | Should -Be 8
            }
        }

        It '真实解析：已正确转义的字符串在修复过程中应原样保留' {
            if (-not $script:PSTomlAvailable) {
                Set-ItResult -Skipped -Because 'PSToml 模块不可用'
                return
            }
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 混合场景：坏路径触发修复，author 含已正确转义的 \\ 与 \"，验证保护机制不误伤
                Mock -CommandName Get-Content -ModuleName IPAP { return @'
[paths]
source_dir = "C:\Users\someone\images"
[project]
author = "Lucas\\G\"old"
'@ }

                $config = [IPAPConfiguration]::Load($p)

                # 坏路径被修复为正确值
                $config.Paths.SourceDir | Should -Be 'C:\Users\someone\images'
                # 合法转义原样保留：\\ -> \，\" -> "
                $config.Project.Author | Should -Be 'Lucas\G"old'
            }
        }
    }

    Context 'MergeSettings 方法 - 浅合并逻辑（L1）' {
        It '用户配置覆盖默认值时应使用用户值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP {
                    return @{ app_settings = @{ model_select = 'custom-model' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.ModelSelect | Should -Be 'custom-model'
                $config.App.UpscaleTimeoutSec | Should -Be 3600
                # 判别锚点：未被覆盖的 max_workers 应为默认表的 8，证明其余默认值来自默认表而非类内兜底
                $config.App.MaxWorkers | Should -Be 8
            }
        }

        It '用户配置中存在默认配置没有的顶级键时应直接添加，未知子键应被丢弃' {
            InModuleScope IPAP {
                $defaultSettings = @{
                    paths        = @{ source_dir = 'default_source' }
                    app_settings = @{ model_select = 'models-se' }
                }
                $parsedSettings = @{
                    app_settings = @{ model_select = 'custom-model'; brand_new = 'unknown' }
                    custom_flag  = $true
                }

                # 直接调用隐藏静态方法，验证浅合并的两个边界分支
                $merged = [IPAPConfiguration]::MergeSettings($parsedSettings, $defaultSettings)

                # 顶级未知键应被添加进合并结果
                @($merged.Keys | Sort-Object) | Should -Be @('app_settings', 'custom_flag', 'paths')
                $merged['custom_flag'] | Should -Be $true
                # 已知子键被覆盖，未知子键被丢弃
                $merged['app_settings']['model_select'] | Should -Be 'custom-model'
                @($merged['app_settings'].Keys | Sort-Object) | Should -Be @('model_select')
                # 未被用户覆盖的默认子键应保留，且原始默认表不应被污染
                $merged['paths']['source_dir'] | Should -Be 'default_source'
                $defaultSettings.ContainsKey('custom_flag') | Should -Be $false
            }
        }

        It '用户配置覆盖嵌套哈希表的子键时应只影响被覆盖的子键' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP {
                    return @{ webp = @{ quality = 75 } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.WebpQuality | Should -Be 75
                $config.App.WebpEnabled | Should -Be $true
                $config.App.WebpLossless | Should -Be $true
                # 判别锚点：只覆盖 quality 时 max_workers 仍应取默认表的 8，证明其余子键未被连带清空
                $config.App.MaxWorkers | Should -Be 8
            }
        }
    }

    Context 'ReadConfigFile - 读取流程（L1）' {
        It 'config.toml 存在时应尝试读取文件内容' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP { return @{} }

                [IPAPConfiguration]::Load($p) | Out-Null

                # 配置文件存在时应恰好读取一次，防止重复读取掩盖流程回归
                Should -Invoke -CommandName Get-Content -Times 1 -Exactly
            }
        }
    }

    Context 'ReadConfigFile - OrderedDictionary 转换（L4）' {
        It 'OrderedDictionary 类型的子配置应被转换为 Hashtable' {
            if (-not $script:PSTomlAvailable) {
                Set-ItResult -Skipped -Because 'PSToml 模块不可用'
                return
            }
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 真实 TOML：PSToml 解析出的子配置块天然是 OrderedDictionary，故此处无 Mock，验证真实解析
                Mock -CommandName Get-Content -ModuleName IPAP { return @'
[paths]
base_project_dir = "real_base"
source_dir = "real_source"
'@ }

                # 直接调用隐藏静态方法，检查 MergeSettings 之前的真实返回值类型
                $rawSettings = [IPAPConfiguration]::ReadConfigFile($p)

                # 顶层被强转为 Hashtable；真实解析出的 OrderedDictionary 子块应已被脱壳为 Hashtable
                $rawSettings | Should -BeOfType 'System.Collections.Hashtable'
                $rawSettings['paths'] | Should -BeOfType 'System.Collections.Hashtable'
                $rawSettings['paths']['base_project_dir'] | Should -Be 'real_base'
                $rawSettings['paths']['source_dir'] | Should -Be 'real_source'
            }
        }
    }

    Context '边界情况 - 多种配置组合（L3）' {
        It '所有配置区块都存在时应正确合并' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP {
                    return @{
                        paths        = @{ source_dir = 'custom_source' }
                        project      = @{ author = '鲁迅'; original_title = '呐喊' }
                        app_settings = @{ model_select = 'models-pro'; max_workers = 4 }
                        upscale      = @{ upscale_ratio = 4 }
                        webp         = @{ quality = 80 }
                    }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.Paths.SourceDir | Should -Be 'custom_source'
                $config.Project.Author | Should -Be '鲁迅'
                $config.Project.OriginalTitle | Should -Be '呐喊'
                $config.App.ModelSelect | Should -Be 'models-pro'
                $config.App.MaxWorkers | Should -Be 4
                $config.App.UpscaleRatio | Should -Be 4
                $config.App.WebpQuality | Should -Be 80
            }
        }

        It '仅有 project 配置时其他子配置应为默认值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP {
                    return @{ project = @{ author = '鲁迅' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                # 用户显式设置的值应生效
                $config.Project.Author | Should -Be '鲁迅'
                # 其余四个区块各取一个默认键，逐区块证明「未出现在用户配置中时取默认表值」
                $config.Paths.BaseProjectDir | Should -Be ''
                $config.App.ModelSelect | Should -Be 'models-se'
                # 判别锚点：默认表给 8，类内兜底给 ProcessorCount/2，此处为 8 才能证明上述默认值来自默认表
                $config.App.MaxWorkers | Should -Be 8
                $config.App.UpscaleRatio | Should -Be 2
                $config.App.WebpQuality | Should -Be 100
            }
        }

        It '配置文件中 paths 为 null 时应回退为空字典并保留默认路径行为' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 'paths' 键存在但值为 null，MergeSettings 会用 null 整体覆盖默认区块
                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP { return @{ paths = $null } }

                $config = [IPAPConfiguration]::Load($p)

                # 触发 Load 中的 'paths' ?? @{} 回退分支，两个子键取不到值后落回空字符串
                $config.Paths.ProjectRoot | Should -Be $p
                $config.Paths.BaseProjectDir | Should -Be ''
                $config.Paths.SourceDir | Should -Be ''
            }
        }
    }

    Context '静态方法 Load - 配置块类型非法（L2）' {
        It 'paths 键存在但不是字典类型时应抛出 ArgumentException' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName ConvertFrom-Toml -ModuleName IPAP { return @{ paths = 'not_a_dict' } }

                { [IPAPConfiguration]::Load($p) } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'paths' 必须是 IDictionary 类型，当前值类型为 'String'"
            }
        }
    }

    Context '构造函数 - 独立性验证（L5）' {
        It '修改一个实例不应影响另一个实例' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $toolConfig = [ToolConfiguration]::new($pathConfig, @{ paths = @{} })

                $appConfig1 = [ApplicationConfiguration]::new(@{ webp = @{ quality = 50 } })
                $projectConfig1 = [ProjectConfiguration]::new(@{ project = @{ author = '作者A' } })

                $appConfig2 = [ApplicationConfiguration]::new(@{ webp = @{ quality = 90 } })
                $projectConfig2 = [ProjectConfiguration]::new(@{ project = @{ author = '作者B' } })

                $config1 = [IPAPConfiguration]::new($pathConfig, $toolConfig, $appConfig1, $projectConfig1)
                $config2 = [IPAPConfiguration]::new($pathConfig, $toolConfig, $appConfig2, $projectConfig2)

                $config1.App.WebpQuality | Should -Be 50
                $config1.Project.Author | Should -Be '作者A'
                $config2.App.WebpQuality | Should -Be 90
                $config2.Project.Author | Should -Be '作者B'
            }
        }
    }
}
