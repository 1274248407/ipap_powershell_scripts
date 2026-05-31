#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ProjectManager - Get-ProjectBriefInfo 验收测试
.DESCRIPTION
    验收测试 Get-ProjectBriefInfo 函数在真实环境中的项目信息获取能力。
#>

Describe 'Get-ProjectBriefInfo Acceptance Tests' -Tag 'Get-ProjectBriefInfo', 'IPAP.ProjectManager', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.ProjectManager module not found at: $ModulePath" -ForegroundColor Red
        }
    }

    AfterAll {
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常信息获取' {
        It '应能获取项目信息并返回格式化文本' {
            Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '作者名' } { return 'TestAuthor' }
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '原作品名' } { return 'OriginalTitle' }
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '中文译名' } { return 'ChineseTitle' }
            Mock -ModuleName IPAP.ProjectManager Read-MultiLineInput {
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

        It '返回格式应包含所有模板部分' {
            Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '作者名' } { return 'Author' }
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '原作品名' } { return 'Test' }
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '中文译名' } { return 'TestChinese' }
            Mock -ModuleName IPAP.ProjectManager Read-MultiLineInput { return @() }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '项目简介'
            $formatted | Should -Match '原文简介'
            $formatted | Should -Match '中文简介'
        }
    }

    Context '多行简介测试' {
        It '应支持多行项目简介' {
            Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '作者名' } { return 'Author' }
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '原作品名' } { return 'Test' }
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -match '中文译名' } { return 'TestChinese' }
            Mock -ModuleName IPAP.ProjectManager Read-MultiLineInput {
                param ($Prompt)
                if ($Prompt -like '*原文简介*')
                {
                    return @('世界观概述', '详细内容')
                }
                else
                {
                    return @()
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '世界观概述'
            $formatted | Should -Match '详细内容'
        }
    }

    Context '参数化调用验收测试' {
        It '传入所有参数时应生成完整的项目信息' {
            Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
            Mock -ModuleName IPAP.ProjectManager Read-Host { throw '不应调用 Read-Host' }
            Mock -ModuleName IPAP.ProjectManager Read-MultiLineInput { throw '不应调用 Read-MultiLineInput' }

            $formatted, $projectName = Get-ProjectBriefInfo `
                -Author '鲁迅' `
                -OriginalTitle '呐喊' `
                -ChineseTitle '呐喊' `
                -OriginalOverview '这是呐喊的原文简介' `
                -ChineseOverview '这是呐喊的中文简介'

            $projectName | Should -Be '[鲁迅] 呐喊'
            $formatted | Should -Match '呐喊'
            $formatted | Should -Match '这是呐喊的原文简介'
            $formatted | Should -Match '这是呐喊的中文简介'
        }

        It '使用多行简介参数时应保留换行格式' {
            Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
            Mock -ModuleName IPAP.ProjectManager Read-Host { throw '不应调用 Read-Host' }
            Mock -ModuleName IPAP.ProjectManager Read-MultiLineInput { throw '不应调用 Read-MultiLineInput' }

            $formatted, $projectName = Get-ProjectBriefInfo `
                -Author 'Author' `
                -OriginalTitle 'Original Title' `
                -ChineseTitle '中文标题' `
                -OriginalOverview "第一段`n第二段`n第三段" `
                -ChineseOverview "中文第一段`n中文第二段"

            $formatted | Should -Match '第一段'
            $formatted | Should -Match '第二段'
            $formatted | Should -Match '第三段'
            $formatted | Should -Match '中文第一段'
            $formatted | Should -Match '中文第二段'
        }

        It '部分传参时应正确混合使用参数和交互式输入' {
            Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
            Mock -ModuleName IPAP.ProjectManager Read-Host -ParameterFilter { $Prompt -eq '作品中文译名' } { return '交互中文' }
            Mock -ModuleName IPAP.ProjectManager Read-MultiLineInput {
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

            $formatted, $projectName = Get-ProjectBriefInfo `
                -Author '交互作者' `
                -OriginalTitle '交互作品' `
                -OriginalOverview '原文简介' `
                -ChineseOverview '中文简介'

            $formatted | Should -Match '原文简介'
            $formatted | Should -Match '中文简介'
            $projectName | Should -Match '交互作者'
            $projectName | Should -Match '交互作品'
            $formatted | Should -Match '交互中文'
        }
    }
}