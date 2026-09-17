#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - ProjectConfiguration 单元测试
.DESCRIPTION
    测试 ProjectConfiguration 类的构造函数、属性初始化和 GetProjectName 方法。
    覆盖正常路径、缺失键、非法配置值以及 GetProjectName 的各种组合边界。
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

    Context '构造函数 - 完整配置' {
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

    Context '构造函数 - 缺失 project 键' {
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
                $config = [ProjectConfiguration]::new(@{})

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
                $config.ChineseTitle | Should -Be ''
                $config.OriginalOverview | Should -Be ''
                $config.ChineseOverview | Should -Be ''
            }
        }
    }

    Context '构造函数 - 部分键缺失' {
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

    Context '构造函数 - 空值覆盖' {
        It 'settings 中值为空字符串时应接受空字符串' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = ''
                        original_title = ''
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.Author | Should -Be ''
                $config.OriginalTitle | Should -Be ''
            }
        }
    }

    Context '构造函数 - 非法 project 值（Level 2 逻辑异常）' {
        It 'project 为 null 时应抛出逻辑异常而非系统异常' {
            InModuleScope IPAP {
                { [ProjectConfiguration]::new(@{ project = $null }) } |
                    Should -Throw -ExpectedMessage "*配置项 'project' 必须是 Hashtable 类型*"
            }
        }

        It 'project 为字符串时应抛出逻辑异常而非系统异常' {
            InModuleScope IPAP {
                { [ProjectConfiguration]::new(@{ project = '呐喊' }) } |
                    Should -Throw -ExpectedMessage "*配置项 'project' 必须是 Hashtable 类型*"
            }
        }

        It 'project 为数组时应抛出逻辑异常' {
            InModuleScope IPAP {
                { [ProjectConfiguration]::new(@{ project = @('呐喊') }) } |
                    Should -Throw -ExpectedMessage "*配置项 'project' 必须是 Hashtable 类型*"
            }
        }

        It 'project 为有序字典时应抛出逻辑异常（本项目约定子配置块统一为 Hashtable）' {
            InModuleScope IPAP {
                { [ProjectConfiguration]::new(@{ project = [ordered]@{ author = '鲁迅' } }) } |
                    Should -Throw -ExpectedMessage "*配置项 'project' 必须是 Hashtable 类型*"
            }
        }

        It '异常消息应包含实际的类型名以便排查' {
            InModuleScope IPAP {
                { [ProjectConfiguration]::new(@{ project = '呐喊' }) } |
                    Should -Throw -ExpectedMessage "*当前值类型为 'String'*"
            }
        }
    }

    Context 'GetProjectName 方法 - 正常路径' {
        It '作者和标题都存在时应返回 [作者] 标题 格式' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = '鲁迅'
                        original_title = '呐喊'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be '[鲁迅] 呐喊'
            }
        }

        It '作者和标题都不同时应正确拼接' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = 'TestAuthor'
                        original_title = 'TestTitle'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be '[TestAuthor] TestTitle'
            }
        }
    }

    Context 'GetProjectName 方法 - 边界情况' {
        It '作者为空时应仅返回标题' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = ''
                        original_title = '呐喊'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be '呐喊'
            }
        }

        It '标题为空时应仅返回空字符串（作者不满足非空白条件）' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = '鲁迅'
                        original_title = ''
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be ''
            }
        }

        It '作者为 null 时应仅返回标题' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        original_title = '呐喊'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be '呐喊'
            }
        }

        It '标题为 null 时应仅返回空字符串' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author = '鲁迅'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                # original_title 未在 settings 中，构造函数已将其初始化为空字符串（而非 null）
                # GetProjectName 中 IsNullOrWhiteSpace('') 为 true，回退到 return $this.OriginalTitle（''）
                $config.GetProjectName() | Should -Be ''
            }
        }

        It '作者和标题都为空时应返回空字符串' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = ''
                        original_title = ''
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be ''
            }
        }

        It '作者和标题都为 null 时应返回空字符串' {
            InModuleScope IPAP {
                $config = [ProjectConfiguration]::new(@{})

                $config.GetProjectName() | Should -Be ''
            }
        }

        It '作者为空白字符串时应仅返回标题' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = '   '
                        original_title = '呐喊'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be '呐喊'
            }
        }

        It '标题为空白字符串时应返回该空白字符串（作者满足但标题不满足非空白条件）' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = '鲁迅'
                        original_title = '   '
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                # GetProjectName: IsNullOrWhiteSpace('   ') 为 true，回退到 return $this.OriginalTitle
                $config.GetProjectName() | Should -Be '   '
            }
        }
    }

    Context 'GetProjectName 方法 - 特殊字符' {
        It '作者和标题含中文特殊字符时应正确拼接' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = '作者（测试）'
                        original_title = '标题【测试】'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be '[作者（测试）] 标题【测试】'
            }
        }

        It '标题含空格时应保留空格' {
            InModuleScope IPAP {
                $settings = @{
                    project = @{
                        author         = 'Author'
                        original_title = 'My Title'
                    }
                }
                $config = [ProjectConfiguration]::new($settings)

                $config.GetProjectName() | Should -Be '[Author] My Title'
            }
        }
    }

    Context '构造函数验证' {
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

    Context '属性类型验证' {
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

    Context '独立性验证' {
        It '多个实例之间不应互相影响' {
            InModuleScope IPAP {
                $settings1 = @{ project = @{ author = '作者A'; original_title = '标题A' } }
                $settings2 = @{ project = @{ author = '作者B'; original_title = '标题B' } }
                $config1 = [ProjectConfiguration]::new($settings1)
                $config2 = [ProjectConfiguration]::new($settings2)

                $config1.GetProjectName() | Should -Be '[作者A] 标题A'
                $config2.GetProjectName() | Should -Be '[作者B] 标题B'
            }
        }
    }
}
