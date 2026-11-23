#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ReadmeToml 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖 README.toml 读取：
    L1 正常读取、L2 缺失/空文件/损坏文件、L3 只含部分段、L4 损坏时备份为 .bad 并记 Error、L5 返回类型。
#>

Describe 'Get-ReadmeToml Unit Tests' -Tag 'Get-ReadmeToml', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
        Import-Module (Join-Path $ProjectRoot 'output\RequiredModules\PSToml') -Force -Global
        $Script:ProjectRoot = $ProjectRoot
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        [string]$Script:ProjectDir = New-Item -ItemType Directory -Path 'TestDrive:\proj' -Force |
            Select-Object -ExpandProperty FullName
        [string]$Script:ReadmePath = Join-Path $Script:ProjectDir 'README.toml'
        Mock Write-LogEntry -ModuleName IPAP { }
    }

    Context 'L1 正常读取' {
        It '有效文件应返回可读对象' {
            Set-Content -LiteralPath $Script:ReadmePath -Encoding utf8 -Value @'
[run]
status = "running"
project_level = 1
realcugan_scale = 2
model = "models-se"
'@

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            $Result.run.status | Should -BeExactly 'running'
            $Result.run.project_level | Should -Be 1
            $Result.run.model | Should -BeExactly 'models-se'
        }
    }

    Context 'L2 缺失与异常' {
        It '文件不存在时应返回 $null' {
            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            $Result | Should -BeNullOrEmpty
        }

        It '空文件应返回 $null 且不备份' {
            Set-Content -LiteralPath $Script:ReadmePath -Value '' -Encoding utf8

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            $Result | Should -BeNullOrEmpty
            Test-Path -LiteralPath "$($Script:ReadmePath).bad" | Should -BeFalse
        }

        It '损坏文件应返回 $null 而不抛异常' {
            Set-Content -LiteralPath $Script:ReadmePath -Value '[run' -Encoding utf8

            { InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                    param($Dir)
                    Get-ReadmeToml -ProjectDir $Dir
                } } | Should -Not -Throw
        }
    }

    Context 'L3 只含部分段' {
        It '只有 [project] 时其余段应为 $null' {
            Set-Content -LiteralPath $Script:ReadmePath -Encoding utf8 -Value @'
[project]
author = "某人"
'@

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            $Result.project.author | Should -BeExactly '某人'
            $Result.run.status | Should -BeNullOrEmpty
        }
    }

    Context 'L4 损坏文件的处置' {
        It '解析失败时应把原文件改名为 .bad 并记 Error' {
            Set-Content -LiteralPath $Script:ReadmePath -Value '[run' -Encoding utf8

            $null = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            Test-Path -LiteralPath $Script:ReadmePath | Should -BeFalse
            Test-Path -LiteralPath "$($Script:ReadmePath).bad" | Should -BeTrue
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Error' -and $Message -like '*已备份为*' }
        }

        It '已有 .bad 时应覆盖旧备份' {
            Set-Content -LiteralPath "$($Script:ReadmePath).bad" -Value '旧备份' -Encoding utf8
            Set-Content -LiteralPath $Script:ReadmePath -Value '[run' -Encoding utf8

            $null = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            Get-Content -LiteralPath "$($Script:ReadmePath).bad" -Raw | Should -Match '\A\[run'
        }

        It '损坏文件且备份失败时应记 Error 且不抛异常' {
            Set-Content -LiteralPath $Script:ReadmePath -Value '[run' -Encoding utf8
            Mock -ModuleName IPAP Move-Item { throw 'locked' }

            { InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                    param($Dir)
                    Get-ReadmeToml -ProjectDir $Dir
                } } | Should -Not -Throw

            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Error' -and $Message -like '*备份失败*' }
        }
    }

    Context 'L4 依赖在模块加载时装好' {
        It 'PSModulePath 为空时模块内仍应能看见 ConvertFrom-Toml' {
            # 本机已安装 PSToml 时 Get-Command 会自动加载，必须同时断开模块与 PSModulePath 才算「干净机器」；
            # 这正是 v3.0.0 漏掉的那条路径：配置加载时 -Scope Local 的导入出了类方法就失效
            [string]$Script:SavedModulePath = $env:PSModulePath
            try {
                $env:PSModulePath = ''
                Remove-Module PSToml -Force -ErrorAction SilentlyContinue
                Remove-Module IPAP -Force -ErrorAction SilentlyContinue
                Import-Module (Join-Path $Script:ProjectRoot 'source\IPAP.psd1') -Force -Global

                $Visible = & (Get-Module IPAP) { [bool](Get-Command 'ConvertFrom-Toml' -ErrorAction SilentlyContinue) }
                $Visible | Should -BeTrue
            }
            finally {
                $env:PSModulePath = $Script:SavedModulePath
                # 后续用例依赖真实解析与模块内 Mock，把模块与 PSToml 恢复到常规状态
                Remove-Module IPAP -Force -ErrorAction SilentlyContinue
                Import-Module (Join-Path $Script:ProjectRoot 'source\IPAP.psd1') -Force -Global
                Import-Module (Join-Path $Script:ProjectRoot 'output\RequiredModules\PSToml') -Force -Global
            }
        }

        It 'PSToml 不可用时应记 Warning 并按无记录处理' {
            Set-Content -LiteralPath $Script:ReadmePath -Encoding utf8 -Value "[run]`nstatus = `"running`""
            # 模拟安装不完整：模块内看不到 ConvertFrom-Toml
            Mock -ModuleName IPAP Get-Command { return $null }

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*PSToml 模块不可用*' }
            # 不能把一份读不出来的好文件改名成 .bad
            Test-Path -LiteralPath $Script:ReadmePath | Should -BeTrue
        }
    }

    Context 'L2 读取失败' {
        It '读取文件失败时应记 Warning 并按无记录处理' {
            Set-Content -LiteralPath $Script:ReadmePath -Value '{}' -Encoding utf8
            Mock -ModuleName IPAP Get-Content { throw 'io error' }

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*README.toml 读取失败*' }
        }
    }

    Context 'L5 输出契约' {
        It '成功时应返回单个有序字典对象' {
            Set-Content -LiteralPath $Script:ReadmePath -Encoding utf8 -Value @'
[run]
status = "done"
'@

            $Result = InModuleScope IPAP -Parameters @{ Dir = $Script:ProjectDir } -ScriptBlock {
                param($Dir)
                Get-ReadmeToml -ProjectDir $Dir
            }

            , $Result | Should -HaveCount 1
            $Result | Should -BeOfType ([System.Collections.Specialized.OrderedDictionary])
        }
    }
}
