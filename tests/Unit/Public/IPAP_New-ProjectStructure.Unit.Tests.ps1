#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - New-ProjectStructure 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五个级别覆盖 New-ProjectStructure 的全部分支与输出字段：
    L1 正常流程      —— Context 'L1 正常执行路径'
    L2 异常流程      —— Context 'L2 异常流程'
    L3 边界数据      —— Context 'L3 参数契约与边界数据'
    L4 分支与循环    —— Context 'L4 目录已存在处理' / Context 'L4 ShouldProcess 与 WhatIf'
    L5 输出字段验证  —— Context 'L5 输出字段验证'

    已知不可测分支（源码第 53-57 行「用户取消覆盖 -> return $null」）：
    $PSCmdlet.ShouldContinue 在 Pester 非交互宿主下抛出 MethodInvocationException
    （内含 NullReferenceException，根因为 stdin 重定向）；真控制台下则阻塞等待输入；
    $Host 为只读变量无法 Mock；-Confirm:$false 与 -WhatIf 均无法使其返回 $false。
    唯一可行手段是以 Start-Process -RedirectStandardInput 启动整个 pwsh 进程，
    不属于单元测试做法。该分支已登记至 doc/将来要改的地方.md（make it work / 重要且紧急）。

    临时用例标注【临时】者，随 Write-LogEntry 回归纯日志函数后须删除，原因见用例内注释。
.INPUTS
    无
.OUTPUTS
    无
.NOTES
    Author:  lucas_gold
#>

Describe 'New-ProjectStructure Unit Tests' -Tag 'New-ProjectStructure', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 模块外部依赖在此建立默认基线；场景差异由各 It 内部覆盖
        $script:NewItemCalls = [System.Collections.Generic.List[string]]::new()
        $script:NewItemIndex = 0

        # Write-LogEntry 是模块内命令，必须使用 -ModuleName IPAP；
        # 全局 Mock 无法拦截模块内调用，且 Should -Invoke -ModuleName 将找不到该 Mock
        Mock Write-LogEntry -ModuleName IPAP { }

        # 冻结日期使路径断言精确且与运行日期、时区无关
        # 源码第 45 行 Get-Date -Format 'yyyy-MM-dd' 的真实输出正是此类字符串
        # Write-LogEntry 的时间戳取自 [DateTime]::Now（不经过 Get-Date），不受影响
        Mock Get-Date -ModuleName IPAP { '2026-01-01' }

        Mock Test-Path -ModuleName IPAP { return $false }
        Mock New-Item -ModuleName IPAP {
            $script:NewItemCalls.Add([string]$Path) | Out-Null
        }
    }

    Context 'L1 正常执行路径' {
        It '应返回项目目录完整路径（日期已冻结）' {
            $Result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject'

            $Result | Should -BeOfType [string]
            $Result | Should -BeExactly 'C:\Projects\2026-01-01_TestProject'
        }

        It '带空格的路径与项目名应正确处理' {
            $Result = New-ProjectStructure -BaseDir 'C:\Program Files\Projects' -ProjectName 'Test Project'

            $Result | Should -BeExactly 'C:\Program Files\Projects\2026-01-01_Test Project'
        }
    }

    Context 'L4 目录已存在处理' {
        It '目录已存在且指定 -Force 时应跳过确认直接覆盖创建' {
            Mock Test-Path -ModuleName IPAP { return $true }

            $Result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'ExistingProject' -Force

            Should -Invoke -ModuleName IPAP New-Item -Times 7 -Exactly
            $Result | Should -Not -BeNullOrEmpty
        }

        It '目录已存在且指定 -Force 时应返回项目目录路径' {
            Mock Test-Path -ModuleName IPAP { return $true }

            $Result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'ExistingProject' -Force

            $Result | Should -BeExactly 'C:\Projects\2026-01-01_ExistingProject'
        }
    }

    Context 'L3 参数契约与边界数据' {
        It 'BaseDir 应为 Mandatory 参数' {
            $Command = Get-Command New-ProjectStructure

            $Command.Parameters['BaseDir'].Attributes.Mandatory | Should -Be $true
        }

        It 'ProjectName 应为 Mandatory 参数' {
            $Command = Get-Command New-ProjectStructure

            $Command.Parameters['ProjectName'].Attributes.Mandatory | Should -Be $true
        }

        # 实测：Should -Throw -ExceptionType 无法解析 [ParameterBindingValidationException] 类型字面量
        # （报"找不到类型"），故断言其父类型 ParameterBindingException，
        # 并以 ErrorId 作语言无关的精确判别，区别于缺参数场景
        It 'BaseDir 传空字符串应在参数绑定阶段被拒绝' {
            $ScriptBlock = { New-ProjectStructure -BaseDir '' -ProjectName 'TestProject' }

            $ScriptBlock | Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ErrorId 'ParameterArgumentValidationErrorEmptyStringNotAllowed*'
        }

        It 'ProjectName 传空字符串应在参数绑定阶段被拒绝' {
            $ScriptBlock = { New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName '' }

            $ScriptBlock | Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ErrorId 'ParameterArgumentValidationErrorEmptyStringNotAllowed*'
        }

        It '缺少必填参数应在参数绑定阶段被拒绝' {
            $ScriptBlock = { New-ProjectStructure -ProjectName 'TestProject' }

            $ScriptBlock | Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ErrorId 'MissingMandatoryParameter*'
        }

        It '空白字符串 BaseDir 不被 Mandatory 校验拦截，应进入函数体' {
            # 实测：Mandatory 只拦截空字符串，纯空白串会通过绑定进入函数体
            $Result = New-ProjectStructure -BaseDir '   ' -ProjectName 'TestProject'

            $Result | Should -BeExactly '   \2026-01-01_TestProject'
            $script:NewItemCalls.Count | Should -Be 7
        }
    }

    Context 'L2 异常流程' {
        It 'New-Item 失败应抛出 IOException 且消息精确匹配' {
            Mock New-Item -ModuleName IPAP { throw 'Access denied' }
            $ScriptBlock = { New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' }

            $ScriptBlock | Should -Throw -ExceptionType ([System.IO.IOException]) -ExpectedMessage '创建项目目录失败: Access denied'
        }

        It 'New-Item 失败应记录 Error 级别日志' {
            Mock New-Item -ModuleName IPAP { throw 'Access denied' }
            $ScriptBlock = { New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' }
            $ScriptBlock | Should -Throw

            Should -Invoke -ModuleName IPAP Write-LogEntry -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It '包装异常应保留原始异常为 InnerException' {
            Mock New-Item -ModuleName IPAP { throw 'Access denied' }
            $ScriptBlock = { New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' }

            $ErrorRecord = $ScriptBlock | Should -Throw -ExceptionType ([System.IO.IOException]) -PassThru

            $ErrorRecord.Exception.InnerException | Should -Not -BeNullOrEmpty
            $ErrorRecord.Exception.InnerException.Message | Should -BeExactly 'Access denied'
        }

        It '子目录创建中途失败应走同一 catch 并抛出包装异常' {
            # 前 2 次创建成功（主目录 + 首个子目录），第 3 次抛错，验证循环中途退出同样被捕获
            $script:NewItemFailAt = 3
            Mock New-Item -ModuleName IPAP {
                $script:NewItemCalls.Add([string]$Path) | Out-Null
                $script:NewItemIndex++
                if ($script:NewItemIndex -eq $script:NewItemFailAt) { throw 'Access denied' }
            }
            $ScriptBlock = { New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' }

            $ScriptBlock | Should -Throw -ExceptionType ([System.IO.IOException]) -ExpectedMessage '创建项目目录失败: Access denied'
            $script:NewItemIndex | Should -Be 3
            Should -Invoke -ModuleName IPAP Write-LogEntry -ParameterFilter { $Level -eq 'Error' } -Times 1 -Exactly
        }

        It '【临时】Write-LogEntry 抛异常时真实中断类型为 RuntimeException' {
            # 忠实还原 Write-LogEntry 的 Error 级 throw 契约（source/Private/Write-LogEntry.ps1 第 105-107 行）。
            # 此刻源码第 92 行的 [System.IO.IOException] 包装在真实运行中不可达，
            # 实际抛出的是 Write-LogEntry 抛出的裸字符串 RuntimeException。
            # 该行为已定随 Write-LogEntry 回归纯日志函数而消失，届时须删除本用例。
            Mock Write-LogEntry -ModuleName IPAP {
                param($Level, $Message)
                if ($Level -eq 'Error') { throw $Message }
            }
            Mock New-Item -ModuleName IPAP { throw 'Access denied' }
            $ScriptBlock = { New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' }

            $ScriptBlock | Should -Throw -ExceptionType ([System.Management.Automation.RuntimeException]) -ExpectedMessage '创建项目目录失败: Access denied'
        }
    }

    Context 'L4 ShouldProcess 与 WhatIf' {
        It '-WhatIf 时不应创建任何目录、不应写日志且无输出' {
            $Result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' -WhatIf

            Should -Invoke -ModuleName IPAP New-Item -Times 0 -Exactly
            Should -Invoke -ModuleName IPAP Write-LogEntry -ParameterFilter { $Level -eq 'Info' } -Times 0 -Exactly
            $Result | Should -BeNullOrEmpty
        }

        It '-WhatIf 且目录已存在并指定 -Force 时不应创建任何目录且不抛异常' {
            Mock Test-Path -ModuleName IPAP { return $true }

            $Result = New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' -Force -WhatIf

            Should -Invoke -ModuleName IPAP New-Item -Times 0 -Exactly
            $Result | Should -BeNullOrEmpty
        }
    }

    Context 'L5 输出字段验证' {
        It '应创建的 7 个目录路径应与契约清单完全一致' {
            $ExpectedPaths = @(
                'C:\Projects\2026-01-01_TestProject',
                'C:\Projects\2026-01-01_TestProject\02_Preprocessing\raw_source',
                'C:\Projects\2026-01-01_TestProject\02_Preprocessing\original_non_text_raw',
                'C:\Projects\2026-01-01_TestProject\02_Preprocessing\inpainted',
                'C:\Projects\2026-01-01_TestProject\02_Preprocessing\mask',
                'C:\Projects\2026-01-01_TestProject\03_Typesetting\workfiles',
                'C:\Projects\2026-01-01_TestProject\03_Typesetting\final_pages'
            )

            New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' | Out-Null

            $Missing = @($ExpectedPaths | Where-Object { $script:NewItemCalls -notcontains $PSItem })
            $Unexpected = @($script:NewItemCalls | Where-Object { $ExpectedPaths -notcontains $PSItem })
            $Missing | Should -BeNullOrEmpty
            $Unexpected | Should -BeNullOrEmpty
            $script:NewItemCalls.Count | Should -Be 7
        }

        It '成功路径应记录 1 条开始、6 条子目录、1 条完成共 8 条 Info 日志' {
            New-ProjectStructure -BaseDir 'C:\Projects' -ProjectName 'TestProject' | Out-Null

            Should -Invoke -ModuleName IPAP Write-LogEntry -ParameterFilter { $Level -eq 'Info' } -Times 8 -Exactly
        }
    }
}