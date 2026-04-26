#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ProjectManager - Get-ProjectBriefInfo 单元测试
.DESCRIPTION
    测试 Get-ProjectBriefInfo 函数的项目信息获取逻辑。
#>

Describe 'Get-ProjectBriefInfo Unit Tests' -Tag 'Get-ProjectBriefInfo', 'IPAP.ProjectManager' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
        Mock Read-Host {}
    }

    AfterAll {
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '应返回两个值（格式化文本和项目名）' {
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'TestProject' }
                    '中文译名' { return '测试项目' }
                    '项目简介' { return '' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Not -BeNullOrEmpty
            $projectName | Should -Be 'TestProject'
        }

        It '返回值应包含项目名称' {
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'MyProject' }
                    '中文译名' { return '我的项目' }
                    '项目简介' { return '' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match 'MyProject'
        }

        It '返回值应包含作者中文译名' {
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'Test' }
                    '中文译名' { return '测试' }
                    '项目简介' { return '' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '测试'
        }
    }

    Context '多行简介测试' {
        It '应支持多行项目简介输入' {
            $callCount = 0
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'Test' }
                    '中文译名' { return '测试' }
                    '项目简介' {
                        $callCount++
                        if ($callCount -eq 1) { return '第一行简介' }
                        if ($callCount -eq 2) { return '第二行简介' }
                        return ''
                    }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '第一行简介'
            $formatted | Should -Match '第二行简介'
        }

        It '空行应结束多行输入' {
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'Test' }
                    '中文译名' { return '测试' }
                    '项目简介' { return '' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $projectName | Should -Be 'Test'
        }
    }

    Context '字符串处理测试' {
        It '项目名称应去除首尾空格' {
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return '  TestProject  ' }
                    '中文译名' { return '测试项目' }
                    '项目简介' { return '' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $projectName | Should -Be 'TestProject'
        }

        It '中文译名应去除首尾空格' {
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'Test' }
                    '中文译名' { return '  测试项目  ' }
                    '项目简介' { return '' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '测试项目'
            $formatted | Should -Not -Match '  测试项目  '
        }
    }

    Context '返回值格式测试' {
        It '返回格式应包含模板结构' {
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'Test' }
                    '中文译名' { return '测试' }
                    '项目简介' { return '' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '项目名称'
            $formatted | Should -Match '项目简介'
            $formatted | Should -Match '角色译名表'
            $formatted | Should -Match '名词对照表'
        }
    }
}
