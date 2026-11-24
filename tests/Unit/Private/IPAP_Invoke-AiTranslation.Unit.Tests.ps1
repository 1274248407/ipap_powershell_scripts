#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Invoke-AiTranslation 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖 AI 翻译调用：
    L1 正常解析、L2 请求异常与返回异常、L3 只需要一个字段、L4 请求报文契约、L5 输出契约。
    Invoke-RestMethod 是唯一的外部依赖，全部 Mock，不产生真实网络请求。
    假响应直接在 Mock 体内构造——Mock 注入模块作用域，看不到测试作用域定义的辅助函数。
#>

Describe 'Invoke-AiTranslation Unit Tests' -Tag 'Invoke-AiTranslation', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function Invoke-Translation {
            param ([hashtable]$Params)
            return InModuleScope IPAP -Parameters @{ P = $Params } -ScriptBlock {
                param($P)
                Invoke-AiTranslation @P
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        Mock Write-LogEntry -ModuleName IPAP { }
        $Script:BaseParams = @{
            Endpoint         = 'https://api.example.com/v1/chat/completions'
            Model            = 'test-model'
            ApiKey           = 'sk-test-key'
            OriginalTitle    = '僕の妻'
            OriginalOverview = 'あらすじ本文'
        }
    }

    Context 'L1 正常解析' {
        It '应返回两个中文字段' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                            message = [PSCustomObject]@{ content = '{"chinese_title":"我心爱的妻子","chinese_overview":"简介正文"}' }
                        })
                }
            }

            $Result = Invoke-Translation -Params $Script:BaseParams

            $Result.ChineseTitle | Should -BeExactly '我心爱的妻子'
            $Result.ChineseOverview | Should -BeExactly '简介正文'
        }

        It '返回内容前后空白应被裁掉' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                            message = [PSCustomObject]@{ content = '{"chinese_title":"  标题  ","chinese_overview":"  简介  "}' }
                        })
                }
            }

            (Invoke-Translation -Params $Script:BaseParams).ChineseTitle | Should -BeExactly '标题'
        }
    }

    Context 'L2 失败路径' {
        It 'HTTP 异常时应记 Warning 并返回 $null' {
            Mock -ModuleName IPAP Invoke-RestMethod { throw 'connection refused' }

            Invoke-Translation -Params $Script:BaseParams | Should -BeNullOrEmpty
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*AI 翻译请求失败*' }
        }

        It '返回内容为空时应记 Warning 并返回 $null' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{ choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '' } }) }
            }

            Invoke-Translation -Params $Script:BaseParams | Should -BeNullOrEmpty
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Message -like '*返回内容为空*' }
        }

        It '返回内容不是 JSON 时应记 Warning 并返回 $null' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{ choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '这不是 JSON' } }) }
            }

            Invoke-Translation -Params $Script:BaseParams | Should -BeNullOrEmpty
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Message -like '*不是合法 JSON*' }
        }

        It '两个字段都为空时应记 Warning 并返回 $null' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                            message = [PSCustomObject]@{ content = '{"chinese_title":"","chinese_overview":"  "}' }
                        })
                }
            }

            Invoke-Translation -Params $Script:BaseParams | Should -BeNullOrEmpty
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Message -like '*未返回可用的中文内容*' }
        }
    }

    Context 'L3 只请求需要的字段' {
        It '作者前缀不进入请求体，正文照常翻译' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{ choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"chinese_title":"我心爱的妻子"}' } }) }
            }
            $Params = $Script:BaseParams.Clone()
            $Params['OriginalTitle'] = '[秘密作者] 僕の妻'

            $null = Invoke-Translation -Params $Params

            Should -Invoke -ModuleName IPAP Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                [string]$BodyText = [System.Text.Encoding]::UTF8.GetString($Body)
                $BodyText -like '*僕の妻*' -and $BodyText -notlike '*秘密作者*'
            }
        }

        It '返回后应把作者前缀原样拼回' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{ choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"chinese_title":"我心爱的妻子"}' } }) }
            }
            $Params = $Script:BaseParams.Clone()
            $Params['OriginalTitle'] = '[秘密作者] 僕の妻'

            (Invoke-Translation -Params $Params).ChineseTitle | Should -BeExactly '[秘密作者] 我心爱的妻子'
        }

        It '书名只有作者前缀时不请求译名' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{ choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"chinese_title":"不该用","chinese_overview":"简介"}' } }) }
            }
            $Params = $Script:BaseParams.Clone()
            $Params['OriginalTitle'] = '[秘密作者]'

            $Result = Invoke-Translation -Params $Params

            $Result.ChineseTitle | Should -BeExactly ''
            $Result.ChineseOverview | Should -BeExactly '简介'
        }

        It 'NeedTitle 为 false 时译名字段固定为空' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                            message = [PSCustomObject]@{ content = '{"chinese_title":"不该用","chinese_overview":"简介"}' }
                        })
                }
            }
            $Params = $Script:BaseParams.Clone()
            $Params['NeedTitle'] = $false

            $Result = Invoke-Translation -Params $Params

            $Result.ChineseTitle | Should -BeExactly ''
            $Result.ChineseOverview | Should -BeExactly '简介'
        }

        It 'NeedOverview 为 false 时简介字段固定为空' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                            message = [PSCustomObject]@{ content = '{"chinese_title":"标题","chinese_overview":"不该用"}' }
                        })
                }
            }
            $Params = $Script:BaseParams.Clone()
            $Params['NeedOverview'] = $false

            $Result = Invoke-Translation -Params $Params

            $Result.ChineseTitle | Should -BeExactly '标题'
            $Result.ChineseOverview | Should -BeExactly ''
        }
    }

    Context 'L4 请求报文契约' {
        It '请求体应包含模型名、原文与确定性参数' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{ choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"chinese_title":"标题"}' } }) }
            }

            $null = Invoke-Translation -Params $Script:BaseParams

            Should -Invoke -ModuleName IPAP Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                [string]$BodyText = [System.Text.Encoding]::UTF8.GetString($Body)
                $BodyText -like '*test-model*' -and $BodyText -like '*僕の妻*' -and
                $BodyText -like '*json_object*' -and $BodyText -like '*temperature*0*'
            }
        }

        It '请求体应带上传入的 temperature' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{ choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"chinese_title":"标题"}' } }) }
            }
            $Params = $Script:BaseParams.Clone()
            $Params['Temperature'] = 0.7

            $null = Invoke-Translation -Params $Params

            Should -Invoke -ModuleName IPAP Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                [string]$BodyText = [System.Text.Encoding]::UTF8.GetString($Body)
                $BodyText -match '"temperature"\s*:\s*0\.7'
            }
        }

        It '请求头应带 Bearer 密钥且地址为配置的 endpoint' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{ choices = @([PSCustomObject]@{ message = [PSCustomObject]@{ content = '{"chinese_title":"标题"}' } }) }
            }

            $null = Invoke-Translation -Params $Script:BaseParams

            Should -Invoke -ModuleName IPAP Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.example.com/v1/chat/completions' -and
                $Headers.Authorization -eq 'Bearer sk-test-key'
            }
        }
    }

    Context 'L5 输出契约' {
        It '成功时应返回单个对象且字段为字符串' {
            Mock -ModuleName IPAP Invoke-RestMethod {
                [PSCustomObject]@{
                    choices = @([PSCustomObject]@{
                            message = [PSCustomObject]@{ content = '{"chinese_title":"标题","chinese_overview":"简介"}' }
                        })
                }
            }

            $Result = Invoke-Translation -Params $Script:BaseParams

            , $Result | Should -HaveCount 1
            $Result.ChineseTitle | Should -BeOfType ([string])
            $Result.ChineseOverview | Should -BeOfType ([string])
        }
    }
}
