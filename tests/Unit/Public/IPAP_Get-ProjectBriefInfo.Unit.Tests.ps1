#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ProjectBriefInfo 单元测试
.DESCRIPTION
    测试 Get-ProjectBriefInfo 函数的项目信息获取逻辑。
#>

Describe 'Get-ProjectBriefInfo Unit Tests' -Tag 'Get-ProjectBriefInfo', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        Mock Write-LogEntry -ModuleName IPAP {}
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '应返回两个值（格式化文本和项目名）' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return 'TestAuthor' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return 'OriginalTitle' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '中文标题' }
            Mock -ModuleName IPAP Read-MultiLineInput {
                param ($Prompt)
                if ($Prompt -like '*原文简介*')
                {
                    return @('原文简介第一行', '原文简介第二行')
                }
                else
                {
                    return @('中文简介第一行', '中文简介第二行')
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Not -BeNullOrEmpty
            $projectName | Should -Be '[TestAuthor] OriginalTitle'
        }

        It '返回值应包含项目名称' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return 'Author' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return 'MyProject' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '我的项目' }
            Mock -ModuleName IPAP Read-MultiLineInput {
                param ($Prompt)
                if ($Prompt -like '*原文简介*')
                {
                    return @('原文简介内容')
                }
                else
                {
                    return @('中文简介内容')
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match 'MyProject'
        }

        It '返回值应包含作者中文译名' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return 'Author' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return 'Test' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '测试' }
            Mock -ModuleName IPAP Read-MultiLineInput {
                param ($Prompt)
                if ($Prompt -like '*原文简介*')
                {
                    return @('原文简介内容')
                }
                else
                {
                    return @('中文简介内容')
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '测试'
        }
    }

    Context '多行简介测试' {
        It '应支持多行原文简介输入' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return 'Author' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return 'Test' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '测试' }
            Mock -ModuleName IPAP Read-MultiLineInput {
                param ($Prompt)
                if ($Prompt -like '*原文简介*')
                {
                    return @('First line', 'Second line')
                }
                else
                {
                    return @()
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match 'First line'
            $formatted | Should -Match 'Second line'
        }

        It '空行应结束多行输入' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return 'Author' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return 'Test' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '测试' }
            Mock -ModuleName IPAP Read-MultiLineInput { return @() }

            $formatted, $projectName = Get-ProjectBriefInfo

            $projectName | Should -Be '[Author] Test'
        }
    }

    Context '字符串处理测试' {
        It '原作品名应去除首尾空格' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return 'Author' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return '  TestProject  ' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '测试项目' }
            Mock -ModuleName IPAP Read-MultiLineInput { return @() }

            $formatted, $projectName = Get-ProjectBriefInfo

            $projectName | Should -Be '[Author] TestProject'
        }

        It '作品中文译名应去除首尾空格' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return 'Author' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return 'Test' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '  测试项目  ' }
            Mock -ModuleName IPAP Read-MultiLineInput { return @() }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '测试项目'
            $formatted | Should -Not -Match '  测试项目  '
        }

        It '作者名应去除首尾空格' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return '  Author  ' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return 'Test' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '测试项目' }
            Mock -ModuleName IPAP Read-MultiLineInput { return @() }

            $formatted, $projectName = Get-ProjectBriefInfo

            $projectName | Should -Be '[Author] Test'
        }
    }

    Context '返回值格式测试' {
        It '返回格式应包含模板结构' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return 'Author' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return 'Test' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '测试' }
            Mock -ModuleName IPAP Read-MultiLineInput { return @() }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '项目名称'
            $formatted | Should -Match '项目简介'
            $formatted | Should -Match '原文简介'
            $formatted | Should -Match '中文简介'
            $formatted | Should -Match '  原文：\[Author\] Test'
            $formatted | Should -Match '  中文：\[Author\] 测试'
        }
    }

    Context '参数化调用测试' {
        It '传入所有参数时应直接返回格式化结果，不触发交互式输入' {
            Mock -ModuleName IPAP Read-Host { throw '不应调用 Read-Host' }
            Mock -ModuleName IPAP Read-MultiLineInput { throw '不应调用 Read-MultiLineInput' }

            $formatted, $projectName = Get-ProjectBriefInfo -Author '鲁迅' -OriginalTitle '呐喊' -ChineseTitle '呐喊' -OriginalOverview '原文简介内容' -ChineseOverview '中文简介内容'

            $projectName | Should -Be '[鲁迅] 呐喊'
            $formatted | Should -Match '原文简介内容'
            $formatted | Should -Match '中文简介内容'
        }

        It '仅传部分参数时应对未传参数触发交互式输入' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '中文标题' }
            Mock -ModuleName IPAP Read-MultiLineInput {
                param ($Prompt)
                if ($Prompt -like '*原文简介*')
                {
                    return @('原文简介行')
                }
                else
                {
                    return @('中文简介行')
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo -Author 'Author' -OriginalTitle 'Title'

            $projectName | Should -Be '[Author] Title'
            $formatted | Should -Match '中文标题'
            $formatted | Should -Match '原文简介行'
            $formatted | Should -Match '中文简介行'
        }

        It '使用多行简介参数时应正确处理换行符' {
            Mock -ModuleName IPAP Read-Host { throw '不应调用 Read-Host' }
            Mock -ModuleName IPAP Read-MultiLineInput { throw '不应调用 Read-MultiLineInput' }

            $formatted, $projectName = Get-ProjectBriefInfo `
                -Author 'Author' `
                -OriginalTitle 'Title' `
                -ChineseTitle '标题' `
                -OriginalOverview "第一行`n第二行`n第三行" `
                -ChineseOverview "中文第一行`n中文第二行"

            $formatted | Should -Match '第一行'
            $formatted | Should -Match '第二行'
            $formatted | Should -Match '第三行'
            $formatted | Should -Match '中文第一行'
            $formatted | Should -Match '中文第二行'
        }

        It '参数为空字符串时应视为未提供，触发交互式输入' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return '交互式作者' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return '交互作品' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '中文标题' }
            Mock -ModuleName IPAP Read-MultiLineInput {
                param ($Prompt)
                if ($Prompt -like '*原文简介*')
                {
                    return @('原文简介')
                }
                else
                {
                    return @('中文简介')
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo -Author '' -OriginalTitle '' -ChineseTitle ''

            $projectName | Should -Be '[交互式作者] 交互作品'
            $formatted | Should -Match '交互式作者'
            $formatted | Should -Match '交互作品'
        }

        It '参数为空白字符时应视为未提供，触发交互式输入' {
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作者名' } { return '作者' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '原作品名（原文）' } { return '标题' }
            Mock -ModuleName IPAP Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '中文标题' }
            Mock -ModuleName IPAP Read-MultiLineInput {
                param ($Prompt)
                if ($Prompt -like '*原文简介*')
                {
                    return @('原文简介')
                }
                else
                {
                    return @('中文简介')
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo -Author '  ' -OriginalTitle '  ' -ChineseTitle '  '

            $formatted | Should -Match '原文简介'
            $formatted | Should -Match '中文简介'
            $projectName | Should -Match '作者'
            $projectName | Should -Match '标题'
        }
    }
}