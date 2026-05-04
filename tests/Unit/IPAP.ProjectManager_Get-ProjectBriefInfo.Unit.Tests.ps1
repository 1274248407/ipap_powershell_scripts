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
        Mock -ModuleName IPAP.ProjectManager Read-Host { return 'TestInput' }
    }

    AfterAll {
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '应返回两个值（格式化文本和项目名）' {
            $callOrder = 0
            Mock Read-Host {
                $script:callOrder++
                switch ($script:callOrder)
                {
                    1 { return 'TestAuthor' }    # 作者名
                    2 { return 'OriginalTitle' } # 原作品名
                    3 { return '中文标题' }      # 中文译名
                    4 { return '' }              # 原文简介（空行结束）
                    5 { return '' }              # 中文简介（空行结束）
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Not -BeNullOrEmpty
            $projectName | Should -Be '[TestAuthor] OriginalTitle'
        }

        It '返回值应包含项目名称' {
            $callOrder = 0
            Mock Read-Host {
                $script:callOrder++
                switch ($script:callOrder)
                {
                    1 { return 'Author' }      # 作者名
                    2 { return 'MyProject' }   # 原作品名
                    3 { return '我的项目' }    # 中文译名
                    4 { return '' }            # 原文简介（空行结束）
                    5 { return '' }            # 中文简介（空行结束）
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match 'MyProject'
        }

        It '返回值应包含作者中文译名' {
            $callOrder = 0
            Mock Read-Host {
                $script:callOrder++
                switch ($script:callOrder)
                {
                    1 { return 'Author' }      # 作者名
                    2 { return 'Test' }        # 原作品名
                    3 { return '测试' }        # 中文译名
                    4 { return '' }            # 原文简介（空行结束）
                    5 { return '' }            # 中文简介（空行结束）
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '测试'
        }
    }

    Context '多行简介测试' {
        It '应支持多行原文简介输入' {
            $callOrder = 0
            Mock Read-Host {
                $script:callOrder++
                switch ($script:callOrder)
                {
                    1 { return 'Author' }      # 作者名
                    2 { return 'Test' }        # 原作品名
                    3 { return '测试' }        # 中文译名
                    4 { return 'First line' }  # 原文简介第一行
                    5 { return 'Second line' } # 原文简介第二行
                    6 { return '' }            # 原文简介（空行结束）
                    7 { return '' }            # 中文简介（空行结束）
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match 'First line'
            $formatted | Should -Match 'Second line'
        }

        It '空行应结束多行输入' {
            $callOrder = 0
            Mock Read-Host {
                $script:callOrder++
                switch ($script:callOrder)
                {
                    1 { return 'Author' }      # 作者名
                    2 { return 'Test' }        # 原作品名
                    3 { return '测试' }        # 中文译名
                    4 { return '' }            # 原文简介（空行结束）
                    5 { return '' }            # 中文简介（空行结束）
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $projectName | Should -Be '[Author] Test'
        }
    }

    Context '字符串处理测试' {
        It '项目名称应去除首尾空格' {
            $callOrder = 0
            Mock Read-Host {
                $script:callOrder++
                switch ($script:callOrder)
                {
                    1 { return 'Author' }        # 作者名
                    2 { return '  TestProject  ' } # 原作品名（带空格）
                    3 { return '测试项目' }      # 中文译名
                    4 { return '' }              # 原文简介（空行结束）
                    5 { return '' }              # 中文简介（空行结束）
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $projectName | Should -Be '[Author] TestProject'
        }

        It '中文译名应去除首尾空格' {
            $callOrder = 0
            Mock Read-Host {
                $script:callOrder++
                switch ($script:callOrder)
                {
                    1 { return 'Author' }      # 作者名
                    2 { return 'Test' }        # 原作品名
                    3 { return '  测试项目  ' } # 中文译名（带空格）
                    4 { return '' }            # 原文简介（空行结束）
                    5 { return '' }            # 中文简介（空行结束）
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '测试项目'
            $formatted | Should -Not -Match '  测试项目  '
        }
    }

    Context '返回值格式测试' {
        It '返回格式应包含模板结构' {
            $callOrder = 0
            Mock Read-Host {
                $script:callOrder++
                switch ($script:callOrder)
                {
                    1 { return 'Author' }      # 作者名
                    2 { return 'Test' }        # 原作品名
                    3 { return '测试' }        # 中文译名
                    4 { return '' }            # 原文简介（空行结束）
                    5 { return '' }            # 中文简介（空行结束）
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '项目名称'
            $formatted | Should -Match '项目简介'
            $formatted | Should -Match '原文简介'
            $formatted | Should -Match '中文简介'
        }
    }
}
