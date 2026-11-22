#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-WorkflowRunState 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖运行状态读取：
    L1 正常读取、L2 文件缺失/为空/损坏、L3 字段缺失、L4 损坏时记 Warning、L5 返回类型。

    该函数只读项目根目录下的 `.ipap-run.json`，用 TestDrive 真实文件做夹具。
#>

Describe 'Get-WorkflowRunState Unit Tests' -Tag 'Get-WorkflowRunState', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $Script:ProjectDir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'proj') -Force |
            Select-Object -ExpandProperty FullName
        $Script:StatePath = Join-Path $Script:ProjectDir '.ipap-run.json'
        Mock Write-LogEntry -ModuleName IPAP { }
    }

    Context 'L1 正常读取' {
        It '有效状态文件应返回对象并保留字段' {
            '{"status":"running","projectLevel":1,"realCuganScale":2,"modelSelect":"models-se","textCount":3,"nonTextCount":0,"startedAt":"2026-11-22T10:00:00"}' |
                Set-Content -LiteralPath $Script:StatePath -Encoding utf8

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-WorkflowRunState -ProjectDir $Dir
            }

            $Result.projectLevel | Should -Be 1
            $Result.realCuganScale | Should -Be 2
            $Result.modelSelect | Should -Be 'models-se'
            $Result.textCount | Should -Be 3
            $Result.status | Should -Be 'running'
        }
    }

    Context 'L2 缺失与损坏' {
        It '文件不存在时应返回 $null' {
            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-WorkflowRunState -ProjectDir $Dir
            }

            $Result | Should -BeNullOrEmpty
        }

        It '文件为空时应返回 $null' {
            Set-Content -LiteralPath $Script:StatePath -Value '' -Encoding utf8

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-WorkflowRunState -ProjectDir $Dir
            }

            $Result | Should -BeNullOrEmpty
        }

        It '内容不是合法 JSON 时应返回 $null 而不抛异常' {
            Set-Content -LiteralPath $Script:StatePath -Value '{ not json' -Encoding utf8

            { InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                    param($Dir)
                    Get-WorkflowRunState -ProjectDir $Dir
                } } | Should -Not -Throw

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-WorkflowRunState -ProjectDir $Dir
            }
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'L3 字段缺失' {
        It '只有部分字段时应返回可读对象（缺失字段为 $null）' {
            '{"projectLevel":2}' | Set-Content -LiteralPath $Script:StatePath -Encoding utf8

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-WorkflowRunState -ProjectDir $Dir
            }

            $Result.projectLevel | Should -Be 2
            $Result.modelSelect | Should -BeNullOrEmpty
        }
    }

    Context 'L4 分支' {
        It '损坏文件应记录一次 Warning' {
            Set-Content -LiteralPath $Script:StatePath -Value '{ broken' -Encoding utf8

            $null = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-WorkflowRunState -ProjectDir $Dir
            }

            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*运行状态文件无法解析*' }
        }
    }

    Context 'L5 输出契约' {
        It '成功时应返回单个对象' {
            '{"projectLevel":0}' | Set-Content -LiteralPath $Script:StatePath -Encoding utf8

            $Result = @(InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                    param($Dir)
                    Get-WorkflowRunState -ProjectDir $Dir
                })

            $Result.Count | Should -Be 1
        }
    }
}
