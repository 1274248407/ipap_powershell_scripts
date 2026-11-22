#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Save-WorkflowRunState 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖运行状态写入：
    L1 写入并可回读、L2 目标目录不存在、L3 边界值与中文模型名、L4 覆盖已有文件、L5 文件格式。
#>

Describe 'Save-WorkflowRunState Unit Tests' -Tag 'Save-WorkflowRunState', 'IPAP' {
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
        $Script:BaseParams = @{
            ProjectDir     = $Script:ProjectDir
            ProjectLevel   = 1
            RealCuganScale = 2
            ModelSelect    = 'models-se'
            TextCount      = 3
            NonTextCount   = 0
        }
    }

    Context 'L1 正常写入' {
        It '应写出文件且字段可回读' {
            InModuleScope IPAP -Parameters @{ P = $Script:BaseParams } -ScriptBlock {
                param($P)
                Save-WorkflowRunState @P
            }

            Test-Path -LiteralPath $Script:StatePath | Should -BeTrue
            $State = Get-Content -LiteralPath $Script:StatePath -Raw -Encoding utf8 | ConvertFrom-Json
            $State.status | Should -Be 'running'
            $State.projectLevel | Should -Be 1
            $State.realCuganScale | Should -Be 2
            $State.modelSelect | Should -Be 'models-se'
            $State.textCount | Should -Be 3
        }

        It 'startedAt 应为可解析的时间戳' {
            InModuleScope IPAP -Parameters @{ P = $Script:BaseParams } -ScriptBlock {
                param($P)
                Save-WorkflowRunState @P
            }

            $State = Get-Content -LiteralPath $Script:StatePath -Raw -Encoding utf8 | ConvertFrom-Json
            { [datetime]::Parse($State.startedAt) } | Should -Not -Throw
        }

        It '不应有管道输出' {
            $Result = InModuleScope IPAP -Parameters @{ P = $Script:BaseParams } -ScriptBlock {
                param($P)
                Save-WorkflowRunState @P
            }

            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'L2 异常' {
        It '项目目录不存在时应抛异常（不静默成功）' {
            $Missing = Join-Path $TestDrive 'no-such-dir'

            { InModuleScope IPAP -Parameters @{ Dir = $Missing } -ScriptBlock {
                    param($Dir)
                    Save-WorkflowRunState -ProjectDir $Dir -ProjectLevel 0 -RealCuganScale 2 -ModelSelect 'models-se' -TextCount 1 -NonTextCount 0
                } } | Should -Throw
        }

        It 'ProjectLevel 越界时应被 ValidateRange 拒绝' {
            { InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                    param($Dir)
                    Save-WorkflowRunState -ProjectDir $Dir -ProjectLevel 3 -RealCuganScale 2 -ModelSelect 'models-se' -TextCount 1 -NonTextCount 0
                } } | Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }
    }

    Context 'L3 边界数据' {
        It '零页面时应正常写出 0' {
            InModuleScope IPAP -Parameters @{ P = @{
                    ProjectDir     = $Script:ProjectDir
                    ProjectLevel   = 0
                    RealCuganScale = 4
                    ModelSelect    = 'models-nose'
                    TextCount      = 0
                    NonTextCount   = 0
                } } -ScriptBlock {
                param($P)
                Save-WorkflowRunState @P
            }

            $State = Get-Content -LiteralPath $Script:StatePath -Raw -Encoding utf8 | ConvertFrom-Json
            $State.projectLevel | Should -Be 0
            $State.textCount | Should -Be 0
            $State.modelSelect | Should -Be 'models-nose'
        }
    }

    Context 'L4 覆盖写入' {
        It '再次写入应覆盖旧内容' {
            InModuleScope IPAP -Parameters @{ P = $Script:BaseParams } -ScriptBlock {
                param($P)
                Save-WorkflowRunState @P
            }
            InModuleScope IPAP -Parameters @{ P = @{
                    ProjectDir     = $Script:ProjectDir
                    ProjectLevel   = 2
                    RealCuganScale = 3
                    ModelSelect    = 'models-pro'
                    TextCount      = 9
                    NonTextCount   = 1
                } } -ScriptBlock {
                param($P)
                Save-WorkflowRunState @P
            }

            $State = Get-Content -LiteralPath $Script:StatePath -Raw -Encoding utf8 | ConvertFrom-Json
            $State.projectLevel | Should -Be 2
            $State.textCount | Should -Be 9
            $State.nonTextCount | Should -Be 1
        }
    }

    Context 'L5 文件格式' {
        It '文件应为单个合法 JSON 对象' {
            InModuleScope IPAP -Parameters @{ P = $Script:BaseParams } -ScriptBlock {
                param($P)
                Save-WorkflowRunState @P
            }

            $Raw = Get-Content -LiteralPath $Script:StatePath -Raw -Encoding utf8
            { $Raw | ConvertFrom-Json } | Should -Not -Throw
            ($Raw | ConvertFrom-Json).PSObject.Properties.Name | Should -Contain 'status'
        }
    }
}
