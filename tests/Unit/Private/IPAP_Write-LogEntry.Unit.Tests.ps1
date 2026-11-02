#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Write-LogEntry 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五级要求编写：
    - Level1 正常流程：各级别输出 5 段完整日志（时间戳/级别/调用者/消息/换行）
    - Level2 异常流程：Error 级别不抛异常、不中断执行，输出仍为完整 5 段
    - Level3 边界数据：空串与 $null 消息原样输出、非 Error 空消息、超长/多行/Unicode 消息
    - Level4 分支覆盖：级别颜色四分支、Error 消息红底白字、NoNewline 序列、CallerInfo 格式
    - Level5 输出字段：时间戳格式、级别文本宽度、颜色、NoNewline、文本逐字段验证

    既有契约备注：
    - Write-LogEntry 四个级别均为纯日志函数：只写终端，不抛异常、不中断执行。
      错误传播由调用方显式 throw 强类型异常负责（见 AGENTS.md 防御性编程条目）。
      空消息与 $null 消息均原样输出，日志函数不改写调用方传入的内容。
    - Pester 容器内 Get-PSCallStack 深度恒 >= 31，源码恒走深栈分支 $CallStack[2]；
      浅栈分支（[1]）与无帧分支（'<unknown>:<unknown>:0>'）物理不可达，无法在单元测试
      中构造，故不设占位用例，此处注释说明。

    PS7 新特性审计（AGENTS.md 三强约束：三元 / ??、??= / &&、||）：
    - 本文件第 100 行 $(if ... else ...) 内联表达式已整改为三元
      $($ExpectedLevelColor -eq 'Red' ? 'White' : $ExpectedLevelColor)。
    - 第 101/105 行 if/else 为语句级分支（执行不同断言），三元无法表达，保留。
    - 第 128 行 $script:WriteHostCalls += 数组追加属性能/风格范畴，不在语法审计范围。
    - 全项目 ?? / && / || 旧写法残留已扫描确认无；同型 $(if...) 残留已在
      Confirm-ProjectConfiguration.ps1（7 处）与 New-ReadmeFile.ps1（2 处）一并收敛。
#>

Describe 'Write-LogEntry Unit Tests' -Tag 'Write-LogEntry', 'IPAP' {
    BeforeAll {
        # tests\Unit\Private → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 共享测试数据：级别 → 前置色 映射（来自源码 LevelColorMap 的既定契约）
        $script:LevelColorMap = @{
            'Info'    = 'White'
            'Success' = 'Green'
            'Warning' = 'Yellow'
            'Error'   = 'Red'
        }
        $script:TestMessage = '测试日志消息'

        <#
        .SYNOPSIS
            断言辅助函数：校验 Write-LogEntry 输出的完整 5 段结构
        .DESCRIPTION
            对 Mock Write-Host 捕获的调用参数记录逐段验证 L5 字段：
            段0 时间戳（格式 + DarkGray + 不换行）、段1 级别（文本 + 级别色 + 不换行）、
            段2 调用者（格式 + Cyan + 不换行）、段3 消息（文本 + 颜色 + 不换行）、
            段4 换行（空文本 + 无颜色 + 无 NoNewline）。
            定义在 BeforeAll 中，保证 Pester v6 运行阶段 It 作用域内可见。
        .PARAMETER WriteHostCalls
            Mock Write-Host 捕获的参数记录数组（Text/NoNewline/ForegroundColor/BackgroundColor）
        .PARAMETER ExpectedLevelSegment
            预期的级别段完整文本（如 '| INFO    | '，来自 PadRight(7) 契约）
        .PARAMETER ExpectedLevelColor
            预期的级别前置色（White/Green/Yellow/Red）
        .PARAMETER ExpectedMessage
            预期的消息段文本（允许空字符串，对应空消息场景）
        .PARAMETER ExpectedMessageBackgroundColor
            预期的消息段背景色（仅 Error 为 'Red'，其余传 $null）
        .EXAMPLE
            Assert-CompleteLogLine -WriteHostCalls $script:WriteHostCalls `
                -ExpectedLevelSegment '| INFO    | ' -ExpectedLevelColor 'White' -ExpectedMessage '测试'
        .NOTES
            Author:  lucas_gold
        #>
        function Assert-CompleteLogLine {
            param(
                [Parameter(Mandatory)]
                [object[]] $WriteHostCalls,
                [Parameter(Mandatory)]
                [string] $ExpectedLevelSegment,
                [Parameter(Mandatory)]
                [string] $ExpectedLevelColor,
                [Parameter(Mandatory)]
                [AllowEmptyString()]
                [string] $ExpectedMessage,
                [string] $ExpectedMessageBackgroundColor
            )

            $WriteHostCalls.Count | Should -Be 5 -Because '每次调用应恰输出 5 段'

            # 段0：时间戳格式 yyyy-MM-dd HH:mm:ss.fff（含尾部空格），暗灰色，不换行
            $WriteHostCalls[0].Text | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} $'
            $WriteHostCalls[0].ForegroundColor | Should -Be 'DarkGray'
            $WriteHostCalls[0].BackgroundColor | Should -BeNullOrEmpty
            $WriteHostCalls[0].NoNewline | Should -Be $true

            # 段1：级别段（大写 + PadRight(7)），级别对应颜色，不换行
            $WriteHostCalls[1].Text | Should -Be $ExpectedLevelSegment
            $WriteHostCalls[1].ForegroundColor | Should -Be $ExpectedLevelColor
            $WriteHostCalls[1].BackgroundColor | Should -BeNullOrEmpty
            $WriteHostCalls[1].NoNewline | Should -Be $true

            # 段2：调用者信息（模块:函数:行号 - ），青色，不换行
            $WriteHostCalls[2].Text | Should -Match '^[^:]+:.+:\d+ - $'
            $WriteHostCalls[2].ForegroundColor | Should -Be 'Cyan'
            $WriteHostCalls[2].BackgroundColor | Should -BeNullOrEmpty
            $WriteHostCalls[2].NoNewline | Should -Be $true

            # 段3：消息正文，级别对应颜色（Error 为白字红底），不换行
            $WriteHostCalls[3].Text | Should -Be $ExpectedMessage
            $WriteHostCalls[3].ForegroundColor | Should -Be $($ExpectedLevelColor -eq 'Red' ? 'White' : $ExpectedLevelColor)
            if ($null -eq $ExpectedMessageBackgroundColor)
            {
                $WriteHostCalls[3].BackgroundColor | Should -BeNullOrEmpty
            }
            else
            {
                $WriteHostCalls[3].BackgroundColor | Should -Be $ExpectedMessageBackgroundColor
            }
            $WriteHostCalls[3].NoNewline | Should -Be $true

            # 段4：换行段（空文本，无颜色，不传 NoNewline）
            $WriteHostCalls[4].Text | Should -Be ''
            $WriteHostCalls[4].ForegroundColor | Should -BeNullOrEmpty
            $WriteHostCalls[4].BackgroundColor | Should -BeNullOrEmpty
            $WriteHostCalls[4].NoNewline | Should -Not -Be $true
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # Mock Write-Host 记录每次调用的全部参数（文本/NoNewline/颜色），供 L5 字段验证
        $script:WriteHostCalls = @()
        Mock -CommandName Write-Host -ModuleName IPAP {
            param($Object, $NoNewline, $ForegroundColor, $BackgroundColor)
            $script:WriteHostCalls += [pscustomobject]@{
                Text            = [string]::Join('', @($Object))
                NoNewline       = $NoNewline
                ForegroundColor = [string]$ForegroundColor
                BackgroundColor = [string]$BackgroundColor
            }
        }
    }

    Context '非 Error 级别 - L1 正常流程' {
        It 'Info 级别输出完整 5 段且字段正确' {
            Write-LogEntry -Level Info -Message $script:TestMessage -ErrorAction Stop
            Assert-CompleteLogLine -WriteHostCalls $script:WriteHostCalls `
                -ExpectedLevelSegment '| INFO    | ' `
                -ExpectedLevelColor $script:LevelColorMap['Info'] `
                -ExpectedMessage $script:TestMessage
        }

        It 'Success 级别输出完整 5 段且字段正确' {
            Write-LogEntry -Level Success -Message $script:TestMessage -ErrorAction Stop
            Assert-CompleteLogLine -WriteHostCalls $script:WriteHostCalls `
                -ExpectedLevelSegment '| SUCCESS | ' `
                -ExpectedLevelColor $script:LevelColorMap['Success'] `
                -ExpectedMessage $script:TestMessage
        }

        It 'Warning 级别输出完整 5 段且字段正确' {
            Write-LogEntry -Level Warning -Message $script:TestMessage -ErrorAction Stop
            Assert-CompleteLogLine -WriteHostCalls $script:WriteHostCalls `
                -ExpectedLevelSegment '| WARNING | ' `
                -ExpectedLevelColor $script:LevelColorMap['Warning'] `
                -ExpectedMessage $script:TestMessage
        }

        It '消息段文本与传入 Message 完全一致（含特殊字符）' {
            $SpecialMessage = '含 空格、<尖括号> & [方括号] 的消息内容'
            Write-LogEntry -Level Info -Message $SpecialMessage -ErrorAction Stop
            $script:WriteHostCalls[3].Text | Should -Be $SpecialMessage
        }
    }

    Context 'Error 级别 - L2 纯日志契约' {
        It 'Error 级别输出完整 5 段且消息为白字红底，不抛异常' {
            { Write-LogEntry -Level Error -Message '测试错误消息' -ErrorAction Stop } | Should -Not -Throw
            Assert-CompleteLogLine -WriteHostCalls $script:WriteHostCalls `
                -ExpectedLevelSegment '| ERROR   | ' `
                -ExpectedLevelColor $script:LevelColorMap['Error'] `
                -ExpectedMessage '测试错误消息' `
                -ExpectedMessageBackgroundColor 'Red'
        }

        It 'Error 级别消息段与传入 Message 完全一致且不抛异常' {
            $ErrorMessage = '致命错误ABC'
            { Write-LogEntry -Level Error -Message $ErrorMessage -ErrorAction Stop } | Should -Not -Throw

            $script:WriteHostCalls.Count | Should -Be 5
            $script:WriteHostCalls[3].Text | Should -Be $ErrorMessage
        }
    }

    Context 'Error 级别 - 空消息原样输出（L3 边界）' {
        It '空字符串消息输出空消息段、不抛异常且不被改写为兜底文本' {
            { Write-LogEntry -Level Error -Message '' -ErrorAction Stop } | Should -Not -Throw
            Assert-CompleteLogLine -WriteHostCalls $script:WriteHostCalls `
                -ExpectedLevelSegment '| ERROR   | ' `
                -ExpectedLevelColor $script:LevelColorMap['Error'] `
                -ExpectedMessage '' `
                -ExpectedMessageBackgroundColor 'Red'
            $script:WriteHostCalls[3].Text | Should -Not -Be '未知错误（空消息）' -Because '日志函数不得改写调用方传入的消息'
        }

        It 'null 消息输出空消息段、不抛异常且不被改写为兜底文本' {
            { Write-LogEntry -Level Error -Message $null -ErrorAction Stop } | Should -Not -Throw

            $script:WriteHostCalls.Count | Should -Be 5
            $script:WriteHostCalls[3].Text | Should -Be ''
            $script:WriteHostCalls[3].Text | Should -Not -Be '未知错误（空消息）' -Because '日志函数不得改写调用方传入的消息'
        }
    }

    Context '边界与极端 - L3' {
        It '非 Error 级别空消息不抛异常且消息段为空文本' {
            { Write-LogEntry -Level Info -Message '' -ErrorAction Stop } | Should -Not -Throw
            $script:WriteHostCalls.Count | Should -Be 5
            $script:WriteHostCalls[3].Text | Should -Be ''
        }

        It '超长消息（5000 字符）原样输出到消息段' {
            $LongMessage = 'A' * 5000
            Write-LogEntry -Level Info -Message $LongMessage -ErrorAction Stop
            $script:WriteHostCalls[3].Text | Should -Be $LongMessage
        }

        It '多行消息原样输出到消息段' {
            $MultiLineMessage = "第一行`n第二行`n第三行"
            Write-LogEntry -Level Info -Message $MultiLineMessage -ErrorAction Stop
            $script:WriteHostCalls[3].Text | Should -Be $MultiLineMessage
        }

        It 'Unicode 与中文消息原样输出到消息段' {
            $UnicodeMessage = '中文测试 Ω≈ç√∫˜µ ≤≥÷ 你好世界'
            Write-LogEntry -Level Info -Message $UnicodeMessage -ErrorAction Stop
            $script:WriteHostCalls[3].Text | Should -Be $UnicodeMessage
        }
    }

    Context '调用栈深度 - L3 浅栈边界' {
        It '调用栈只有 2 帧时应取第 2 帧作为调用者' {
            Mock -CommandName Get-PSCallStack -ModuleName IPAP {
                return @(
                    [PSCustomObject]@{ ScriptName = ''; FunctionName = ''; ScriptLineNumber = 0 },
                    [PSCustomObject]@{
                        ScriptName       = 'C:\Modules\TestModule\TestModule.psm1'
                        FunctionName     = 'Test-Function'
                        ScriptLineNumber = 42
                    }
                )
            }

            Write-LogEntry -Level Info -Message '浅栈测试'

            $script:WriteHostCalls.Count | Should -Be 5
            $script:WriteHostCalls[2].Text | Should -Be 'TestModule:Test-Function:42 - '
            Assert-CompleteLogLine -WriteHostCalls $script:WriteHostCalls `
                -ExpectedLevelSegment '| INFO    | ' `
                -ExpectedLevelColor $script:LevelColorMap['Info'] `
                -ExpectedMessage '浅栈测试'
        }

        It '调用栈只有 1 帧时应回退为 unknown 调用者' {
            Mock -CommandName Get-PSCallStack -ModuleName IPAP {
                return @([PSCustomObject]@{ ScriptName = ''; FunctionName = ''; ScriptLineNumber = 0 })
            }

            Write-LogEntry -Level Info -Message '单帧测试'

            $script:WriteHostCalls.Count | Should -Be 5
            $script:WriteHostCalls[2].Text | Should -Be '<unknown>:<unknown>:0 - '
            Assert-CompleteLogLine -WriteHostCalls $script:WriteHostCalls `
                -ExpectedLevelSegment '| INFO    | ' `
                -ExpectedLevelColor $script:LevelColorMap['Info'] `
                -ExpectedMessage '单帧测试'
        }
    }
}