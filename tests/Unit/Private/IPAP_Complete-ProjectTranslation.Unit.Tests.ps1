#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Complete-ProjectTranslation 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖「中文补全」的编排逻辑：
    L1 缺失时补全、L2 未配置/失败时降级、L3 占位符与原文相同、L4 各判定分支、L5 只改内存不改文件。
    Invoke-AiTranslation 是唯一的外部依赖，全部 Mock；环境变量在 BeforeEach/AfterEach 内设置与清理。
#>

Describe 'Complete-ProjectTranslation Unit Tests' -Tag 'Complete-ProjectTranslation', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function New-TestConfig {
            param (
                [Parameter(Mandatory = $true)][string]$Root,
                [string]$Endpoint = 'https://api.example.com/v1/chat/completions',
                [string]$Model = 'test-model',
                [string]$ApiKey = '',
                [double]$Temperature = 0,
                [string]$ChineseTitle = '',
                [string]$ChineseOverview = '',
                [string]$OriginalTitle = '僕の妻',
                [string]$OriginalOverview = 'あらすじ本文'
            )

            return InModuleScope IPAP -Parameters @{
                R = $Root; Ep = $Endpoint; Md = $Model; Ak = $ApiKey; Tp = $Temperature
                Ct = $ChineseTitle; Co = $ChineseOverview; Ot = $OriginalTitle; Oo = $OriginalOverview
            } -ScriptBlock {
                param($R, $Ep, $Md, $Ak, $Tp, $Ct, $Co, $Ot, $Oo)
                $paths = [PathConfiguration]::new($R, 'C:\Projects', 'C:\Images')
                $tools = [ToolConfiguration]::new($paths, @{})
                $app = [ApplicationConfiguration]::new(@{
                        ai = @{ endpoint = $Ep; model = $Md; api_key_env = 'IPAP_AI_API_KEY'; api_key = $Ak; temperature = $Tp; timeout_sec = 15 }
                    })
                $project = [ProjectConfiguration]::new(@{
                        project = @{
                            original_title    = $Ot
                            original_overview = $Oo
                            chinese_title     = $Ct
                            chinese_overview  = $Co
                        }
                    })
                [IPAPConfiguration]::new($paths, $tools, $app, $project)
            }
        }

        function Invoke-Complete {
            param ([object]$Config)
            InModuleScope IPAP -Parameters @{ C = $Config } -ScriptBlock {
                param($C)
                Complete-ProjectTranslation -Config $C
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock Write-LogEntry -ModuleName IPAP { }
        # 默认桩：Pester 6 要求 Should -Invoke 必须先有 Mock，未单独覆盖的用例走「AI 没返回」
        Mock -ModuleName IPAP Invoke-AiTranslation { return $null }
        $Script:Root = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))) -Force |
            Select-Object -ExpandProperty FullName
        $env:IPAP_AI_API_KEY = 'sk-test-key'
    }

    AfterEach {
        Remove-Item Env:\IPAP_AI_API_KEY -ErrorAction SilentlyContinue
    }

    Context 'L1 缺失时补全' {
        It '译名与简介都缺失时应写回内存中的配置' {
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '我心爱的妻子'; ChineseOverview = '中文简介' }
            }
            $Config = New-TestConfig -Root $Script:Root

            Invoke-Complete -Config $Config

            $Config.Project.ChineseTitle | Should -BeExactly '我心爱的妻子'
            $Config.Project.ChineseOverview | Should -BeExactly '中文简介'
        }

        It '只缺简介时应只请求简介' {
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = ''; ChineseOverview = '中文简介' }
            }
            $Config = New-TestConfig -Root $Script:Root -ChineseTitle '我心爱的妻子'

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 1 -Exactly `
                -ParameterFilter { $NeedTitle -eq $false -and $NeedOverview -eq $true }
            $Config.Project.ChineseTitle | Should -BeExactly '我心爱的妻子'
        }
    }

    Context 'L2 降级路径' {
        It '未配置 endpoint 时应跳过且不调用 AI' {
            $Config = New-TestConfig -Root $Script:Root -Endpoint ''

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Message -like '*跳过 AI 补全*' }
        }

        It '配置了 endpoint 但 model 为空时应告警且不调用 AI' {
            $Config = New-TestConfig -Root $Script:Root -Model ''

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*model 为空*' }
        }

        It '密钥环境变量与配置文件都为空时应跳过且不调用 AI' {
            Remove-Item Env:\IPAP_AI_API_KEY -ErrorAction SilentlyContinue
            $Config = New-TestConfig -Root $Script:Root

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Message -like '*未找到 AI 密钥*' }
        }

        It '只在 config.toml 里写了 api_key 时应使用它' {
            Remove-Item Env:\IPAP_AI_API_KEY -ErrorAction SilentlyContinue
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '标题'; ChineseOverview = '简介' }
            }
            $Config = New-TestConfig -Root $Script:Root -ApiKey 'sk-from-config'

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 1 -Exactly `
                -ParameterFilter { $ApiKey -eq 'sk-from-config' }
        }

        It '环境变量与配置文件都有密钥时以环境变量为准' {
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '标题'; ChineseOverview = '简介' }
            }
            $Config = New-TestConfig -Root $Script:Root -ApiKey 'sk-from-config'

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 1 -Exactly `
                -ParameterFilter { $ApiKey -eq 'sk-test-key' }
        }

        It '配置里的 temperature 应传给翻译请求' {
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '标题'; ChineseOverview = '简介' }
            }
            $Config = New-TestConfig -Root $Script:Root -Temperature 0.7

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 1 -Exactly `
                -ParameterFilter { $Temperature -eq 0.7 }
        }

        It 'AI 返回空时应保持原值并记 Warning' {
            Mock -ModuleName IPAP Invoke-AiTranslation { return $null }
            $Config = New-TestConfig -Root $Script:Root -ChineseTitle '原值'

            Invoke-Complete -Config $Config

            $Config.Project.ChineseTitle | Should -BeExactly '原值'
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*AI 补全未成功*' }
        }
    }

    Context 'L3 占位符与原文' {
        It '字段等于 config.toml.example 的占位文本时应补全' {
            Set-Content -LiteralPath (Join-Path $Script:Root 'config.toml.example') -Encoding utf8 -Value @'
[project]
chinese_title = "中文译名"
chinese_overview = "这是中文简介的第一行。"
'@
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '补全的标题'; ChineseOverview = '补全的简介' }
            }
            $Config = New-TestConfig -Root $Script:Root -ChineseTitle '中文译名' -ChineseOverview '这是中文简介的第一行。'

            Invoke-Complete -Config $Config

            $Config.Project.ChineseTitle | Should -BeExactly '补全的标题'
            $Config.Project.ChineseOverview | Should -BeExactly '补全的简介'
        }

        It '中文字段直接填了原文时应补全' {
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '我心爱的妻子'; ChineseOverview = '中文简介' }
            }
            $Config = New-TestConfig -Root $Script:Root -ChineseTitle '僕の妻' -ChineseOverview 'あらすじ本文'

            Invoke-Complete -Config $Config

            $Config.Project.ChineseTitle | Should -BeExactly '我心爱的妻子'
        }

        It '中文字段填的是整句日文时应补全' {
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '我心爱的妻子'; ChineseOverview = '中文简介' }
            }
            $Config = New-TestConfig -Root $Script:Root `
                -ChineseTitle '僕の愛するおっとり妻が寝取られた話' -ChineseOverview '仕事を頑張り、結婚もして夢のマイホームも建てた'

            Invoke-Complete -Config $Config

            $Config.Project.ChineseTitle | Should -BeExactly '我心爱的妻子'
        }
    }

    Context 'L4 判定分支' {
        It '中文已填好时应跳过且不调用 AI' {
            $Config = New-TestConfig -Root $Script:Root -ChineseTitle '我心爱的妻子' -ChineseOverview '中文简介'

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Message -like '*均已填写*' }
        }

        It '原文全空时应告警且不调用 AI' {
            $Config = New-TestConfig -Root $Script:Root -OriginalTitle '' -OriginalOverview ''

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Invoke-AiTranslation -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*原文书名与原文简介都为空*' }
        }

        It 'config.toml.example 损坏时应降级为只判空（占位符不再识别）' {
            Set-Content -LiteralPath (Join-Path $Script:Root 'config.toml.example') -Value '[project' -Encoding utf8
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '补全的标题'; ChineseOverview = '补全的简介' }
            }
            $Config = New-TestConfig -Root $Script:Root -ChineseTitle '中文译名' -ChineseOverview '中文简介'

            Invoke-Complete -Config $Config

            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*占位符判定降级*' }
            # 降级后占位符认不出来，按「已有中文」处理，保持原值
            $Config.Project.ChineseTitle | Should -BeExactly '中文译名'
        }
    }

    Context 'L5 输出契约' {
        It '只改内存对象，不写回 config.toml' {
            Mock -ModuleName IPAP Invoke-AiTranslation {
                [PSCustomObject]@{ ChineseTitle = '我心爱的妻子'; ChineseOverview = '中文简介' }
            }
            [string]$ConfigPath = Join-Path $Script:Root 'config.toml'
            Set-Content -LiteralPath $ConfigPath -Value 'chinese_title = ""' -Encoding utf8
            [string]$Before = Get-Content -LiteralPath $ConfigPath -Raw
            $Config = New-TestConfig -Root $Script:Root

            Invoke-Complete -Config $Config

            Get-Content -LiteralPath $ConfigPath -Raw | Should -BeExactly $Before
            $Config.Project.ChineseTitle | Should -BeExactly '我心爱的妻子'
        }
    }
}
