#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Clear-WorkflowRunState 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖状态标记清理：
    L1 删除已存在文件、L2 文件不存在时不抛异常、L3 幂等、L4 不触碰其他文件、L5 无输出。
#>

Describe 'Clear-WorkflowRunState Unit Tests' -Tag 'Clear-WorkflowRunState', 'IPAP' {
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
    }

    Context 'L1 正常删除' {
        It '文件存在时应删除' {
            Set-Content -LiteralPath $Script:StatePath -Value '{}' -Encoding utf8

            InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Clear-WorkflowRunState -ProjectDir $Dir
            }

            Test-Path -LiteralPath $Script:StatePath | Should -BeFalse
        }
    }

    Context 'L2 异常' {
        It '文件不存在时不应抛异常' {
            { InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                    param($Dir)
                    Clear-WorkflowRunState -ProjectDir $Dir
                } } | Should -Not -Throw
        }

        It '项目目录不存在时不应抛异常' {
            $Missing = Join-Path $TestDrive 'no-such-dir'

            { InModuleScope IPAP -Parameters @{ Dir = $Missing } -ScriptBlock {
                    param($Dir)
                    Clear-WorkflowRunState -ProjectDir $Dir
                } } | Should -Not -Throw
        }
    }

    Context 'L3 幂等' {
        It '连续调用两次应保持无异常' {
            Set-Content -LiteralPath $Script:StatePath -Value '{}' -Encoding utf8

            { InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                    param($Dir)
                    Clear-WorkflowRunState -ProjectDir $Dir
                    Clear-WorkflowRunState -ProjectDir $Dir
                } } | Should -Not -Throw

            Test-Path -LiteralPath $Script:StatePath | Should -BeFalse
        }
    }

    Context 'L4 不误删' {
        It '同目录下的其他文件应保留' {
            Set-Content -LiteralPath $Script:StatePath -Value '{}' -Encoding utf8
            $OtherPath = Join-Path $Script:ProjectDir 'README.md'
            Set-Content -LiteralPath $OtherPath -Value '# 项目记录' -Encoding utf8

            InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Clear-WorkflowRunState -ProjectDir $Dir
            }

            Test-Path -LiteralPath $OtherPath | Should -BeTrue
        }
    }

    Context 'L5 输出契约' {
        It '不应有管道输出' {
            Set-Content -LiteralPath $Script:StatePath -Value '{}' -Encoding utf8

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Clear-WorkflowRunState -ProjectDir $Dir
            }

            $Result | Should -BeNullOrEmpty
        }
    }
}
