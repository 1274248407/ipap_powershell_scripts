#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - ProjectConfiguration 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 覆盖 ProjectConfiguration 构造函数：
    L1 正常流程、L2 非法 project 值、L3 缺失键/空值/有序字典边界、
    L4 分支（含非空 settings 缺 project 键）、L5 5 个属性逐一断言。
    本文件是纯类测试：不 Mock、不做文件 IO、不共享跨用例状态；输入即测试数据，故不设共享夹具。
#>

Describe 'ProjectConfiguration Unit Tests' -Tag 'ProjectConfiguration', 'IPAP', 'Classes' {
    BeforeAll {
        # tests\Unit\Classes → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '构造函数 - 完整配置（L1）' {
        It '应正确读取所有项目配置属性' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author            = '鲁迅'
                        original_title    = '呐喊'
                        chinese_title     = '呐喊'
                        original_overview = 'A collection of short stories'
                        chinese_overview  = '一部短篇小说集'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -Be '鲁迅'
                $config.OriginalTitle | Should -Be '呐喊'
                $config.ChineseTitle | Should -Be '呐喊'
                $config.OriginalOverview | Should -Be 'A collection of short stories'
                $config.ChineseOverview | Should -Be '一部短篇小说集'
            }
        }
    }

    Context '构造函数 - 缺失 project 键（L3）' {
        It 'settings 为 null 时所有属性应为空字符串' {
            InModuleScope IPAP {
                $config = [ProjectConfiguration]::new($null)

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }

        It 'settings 不含 project 键时所有属性应为空字符串' {
            InModuleScope IPAP {
                # 非空 settings 才能让 -and 的右操作数真正求值；空哈希表 @{} 会在左操作数短路
                $config = [ProjectConfiguration]::new(@{ paths = @{} })

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }
    }

    Context '构造函数 - 部分键缺失（L3）' {
        It '仅有 author 时其他属性应为空字符串' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author = '鲁迅'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -Be '鲁迅'
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }

        It '仅有 original_title 时其他属性应为空字符串' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        original_title = '呐喊'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be '呐喊'
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }

        It '仅有部分中文字段时应正确读取' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author        = '鲁迅'
                        chinese_title = '呐喊'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -Be '鲁迅'
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be '呐喊'
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }
    }

    Context '构造函数 - 空值覆盖（L3）' {
        It 'settings 中值为空字符串时应接受空字符串' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author            = ''
                        original_title    = ''
                        chinese_title     = ''
                        original_overview = ''
                        chinese_overview  = ''
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }

        It '键存在但值为 null 时属性应退化为空字符串而非 null（Level 3 边界）' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author            = $null
                        original_title    = $null
                        chinese_title     = $null
                        original_overview = $null
                        chinese_overview  = $null
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                # [string] 属性会将 $null 强制转换为空字符串
                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }
    }

    Context '构造函数 - 非法 project 值（L2）' {
        It 'project 为 null 时应抛出逻辑异常而非系统异常' {
            InModuleScope IPAP {
                { [ProjectConfiguration]::new(@{ project = $null }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'project' 必须是 IDictionary 类型，当前值类型为 'null'"
            }
        }

        It 'project 为字符串时应抛出逻辑异常而非系统异常' {
            InModuleScope IPAP {
                { [ProjectConfiguration]::new(@{ project = '呐喊' }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'project' 必须是 IDictionary 类型，当前值类型为 'String'"
            }
        }

        It 'project 为数组时应抛出逻辑异常' {
            InModuleScope IPAP {
                # 消息含 '[]'，-ExpectedMessage 按通配符解析，方括号必须用反引号转义
                { [ProjectConfiguration]::new(@{ project = @('呐喊') }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'project' 必须是 IDictionary 类型，当前值类型为 'Object``[``]'"
            }
        }

        It 'project 为整数时应抛出逻辑异常' {
            InModuleScope IPAP {
                { [ProjectConfiguration]::new(@{ project = 42 }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'project' 必须是 IDictionary 类型，当前值类型为 'Int32'"
            }
        }
    }

    Context '构造函数 - project 为空字典（L3）' {
        It '空哈希表应被接受且所有属性为空字符串' {
            InModuleScope IPAP {
                $config = [ProjectConfiguration]::new(@{ project = @{} })

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }

        It '空有序字典应被接受且所有属性为空字符串' {
            InModuleScope IPAP {
                $config = [ProjectConfiguration]::new(@{ project = [ordered]@{} })

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }
    }

    Context '构造函数 - 有序字典（[ordered]）应被接受（L4）' {
        It '有序字典应能正常构造并读取全部字段' {
            InModuleScope IPAP {
                $settings = @{
                    project = [ordered]@{
                        author            = '鲁迅'
                        original_title    = '呐喊'
                        chinese_title     = '呐喊'
                        original_overview = 'Overview'
                        chinese_overview  = '简介'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -Be '鲁迅'
                $config.OriginalTitle | Should -Be '呐喊'
                $config.ChineseTitle | Should -Be '呐喊'
                $config.OriginalOverview | Should -Be 'Overview'
                $config.ChineseOverview | Should -Be '简介'
            }
        }

        It '有序字典缺少部分字段时其余字段应保持空字符串' {
            InModuleScope IPAP {
                $settings = @{
                    project = [ordered]@{
                        chinese_title = '呐喊'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be '呐喊'
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }
    }

    Context '构造函数验证（L1）' {
        It '应返回 ProjectConfiguration 实例' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = '鲁迅'
                        original_title = '呐喊'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config | Should -BeOfType [ProjectConfiguration]
            }
        }
    }

    Context '属性类型验证（L5）' {
        It '所有属性应为 string 类型' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author            = 'Author'
                        original_title    = 'Title'
                        chinese_title     = '标题'
                        original_overview = 'Overview'
                        chinese_overview  = '简介'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -BeOfType [string]
                $config.OriginalTitle | Should -BeOfType [string]
                $config.ChineseTitle | Should -BeOfType [string]
                $config.OriginalOverview | Should -BeOfType [string]
                $config.ChineseOverview | Should -BeOfType [string]
            }
        }
    }

    Context '独立性验证（L5）' {
        It '多个实例之间不应互相影响' {
            InModuleScope IPAP {
                $settings1 = @{ project = @{ author = '作者A'; original_title = '标题A' } }
                $settings2 = @{ project = @{ author = '作者B'; original_title = '标题B' } }
                $config1 = [ProjectConfiguration]::new($settings1)
                $config2 = [ProjectConfiguration]::new($settings2)

                $config1.Author | Should -Be '作者A'
                $config1.OriginalTitle | Should -Be '标题A'
                $config2.Author | Should -Be '作者B'
                $config2.OriginalTitle | Should -Be '标题B'
            }
        }
    }
}
