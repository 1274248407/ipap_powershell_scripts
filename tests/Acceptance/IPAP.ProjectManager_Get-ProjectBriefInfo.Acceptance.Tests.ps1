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
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return '[Author] Original Name' }
                    '中文译名' { return '[Author] 中文译名' }
                    '项目简介' { return 'Test overview' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Not -BeNullOrEmpty
            $projectName | Should -Be '[Author] Original Name'
        }

        It '返回格式应包含所有模板部分' {
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'Test' }
                    '中文译名' { return '测试' }
                    '项目简介' { return '' }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '项目简介'
            $formatted | Should -Match '角色译名表'
            $formatted | Should -Match '名词对照表'
        }
    }

    Context '多行简介测试' {
        It '应支持多行项目简介' {
            $callCount = 0
            Mock Read-Host {
                param($Prompt)
                switch -Regex ($Prompt) {
                    '项目名称' { return 'Test' }
                    '中文译名' { return '测试' }
                    '项目简介' {
                        $callCount++
                        if ($callCount -eq 1) { return '世界观概述' }
                        if ($callCount -eq 2) { return '详细内容' }
                        return ''
                    }
                }
            }

            $formatted, $projectName = Get-ProjectBriefInfo

            $formatted | Should -Match '世界观概述'
            $formatted | Should -Match '详细内容'
        }
    }
}
