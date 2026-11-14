#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ProjectBriefInfo 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五级要求编写，测试 Get-ProjectBriefInfo 的
    项目信息获取与格式化模板生成逻辑（交互输入经 Mock 隔离，无需真实控制台）：
    - Level1 正常流程：无参全交互、传参数值、混合参数调用，双值输出
      （$formatted 模板文本 + $projectName 项目名）非空且结构正确
    - Level2 异常流程：交互不可用时（下层 Read-MultiLineInput 抛异常）记录 Error 日志并抛
      InvalidOperationException，保留原始异常为 InnerException，消息指出可绕过的参数
    - Level3 边界数据：空字符串 / 空白字符参数视为未提供转交互；首尾空格在
      交互分支被 Trim（参数直接传入的非空白值不 Trim，属既定行为）；
      Read-MultiLineInput 返回空数组时简介段为空行占位
    - Level4 分支覆盖：5 个参数各自的"传参直达 / 空值转交互"双分支、
      Read-MultiLineInput 按 Prompt 区分原文/中文简介、多行简介换行拼接、
      $tpl 模板 14 行完整拼装
    - Level5 输出字段：$formatted 全量精确断言（Should -BeExactly 完整模板串
      + -split 行级定位断言）、$projectName 逐值精确断言
    测试隔离策略：
    - Mock Read-Host / Read-MultiLineInput（外部交互命令 / 模块内交互函数）
      定义在 BeforeEach（AGENTS 规范），经 $script: 变量承载各用例交互数据；
    - Write-LogEntry 静默屏蔽（全级别纯日志，无状态 Mock）；
    - $script:AuthorName / $script:OriginalTitle / $script:ChineseTitle /
      $script:OriginalOverviewLines / $script:ChineseOverviewLines /
      $script:ThrowOnReadHost 在 BeforeEach 重置、用例内覆盖，测试间不共享状态。
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'Get-ProjectBriefInfo Unit Tests' -Tag 'Get-ProjectBriefInfo', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    BeforeEach {
        # 屏蔽日志输出（Write-LogEntry 为纯日志函数，无状态 Mock）
        Mock Write-LogEntry -ModuleName IPAP { }
        # 每个用例前重置交互数据（避免测试间共享状态）
        $script:AuthorName = 'TestAuthor'
        $script:OriginalTitle = 'TestProject'
        $script:ChineseTitle = '中文标题'
        $script:OriginalOverviewLines = @('原文简介第一行', '原文简介第二行')
        $script:ChineseOverviewLines = @('中文简介第一行', '中文简介第二行')
        $script:ThrowOnReadHost = $false

        # 交互命令 Mock（AGENTS 规范：定义在 BeforeEach，随 $script: 变量延迟取值）
        Mock Read-Host -ModuleName IPAP -ParameterFilter { $Prompt -eq '作者名' } {
            if ($script:ThrowOnReadHost) { throw '不应调用 Read-Host' }
            return $script:AuthorName
        }
        Mock Read-Host -ModuleName IPAP -ParameterFilter { $Prompt -eq '原作品名（原文）' } {
            if ($script:ThrowOnReadHost) { throw '不应调用 Read-Host' }
            return $script:OriginalTitle
        }
        Mock Read-Host -ModuleName IPAP -ParameterFilter { $Prompt -eq '作品中文译名' } {
            if ($script:ThrowOnReadHost) { throw '不应调用 Read-Host' }
            return $script:ChineseTitle
        }
        Mock Read-MultiLineInput -ModuleName IPAP -ParameterFilter { $Prompt -like '*原文简介*' } {
            if ($script:ThrowOnReadHost) { throw '不应调用 Read-MultiLineInput' }
            return $script:OriginalOverviewLines
        }
        Mock Read-MultiLineInput -ModuleName IPAP -ParameterFilter { $Prompt -like '*中文简介*' } {
            if ($script:ThrowOnReadHost) { throw '不应调用 Read-MultiLineInput' }
            return $script:ChineseOverviewLines
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - L1 正常流程' {
        It '无参调用时应通过交互输入返回两个值（格式化文本和项目名）' {
            $Formatted, $ProjectName = Get-ProjectBriefInfo

            $Formatted | Should -Not -BeNullOrEmpty
            $ProjectName | Should -Be '[TestAuthor] TestProject'
        }

        It '返回值应包含项目名称（原文行级精确断言）' {
            $Formatted, $ProjectName = Get-ProjectBriefInfo

            $ProjectName | Should -Be '[TestAuthor] TestProject'
            ($Formatted -split "`n")[2] | Should -BeExactly '  原文：[TestAuthor] TestProject'
        }

        It '返回值应包含作者中文译名（中文行级精确断言）' {
            $Formatted, $ProjectName = Get-ProjectBriefInfo

            ($Formatted -split "`n")[3] | Should -BeExactly '  中文：[TestAuthor] 中文标题'
        }
    }

    Context '交互不可用 - L2 异常流程' {
        It '读取原文简介失败时应记录 Error 日志并抛强类型 InvalidOperationException' {
            Mock Read-MultiLineInput -ModuleName IPAP -ParameterFilter { $Prompt -like '*原文简介*' } {
                throw [System.InvalidOperationException]::new('控制台不可用')
            }

            { Get-ProjectBriefInfo } |
                Should -Throw -ExceptionType ([System.InvalidOperationException]) -ExpectedMessage '*读取【原文简介】失败*'

            Should -Invoke -CommandName Write-LogEntry -ModuleName IPAP -ParameterFilter {
                $Level -eq 'Error' -and $Message -like '*读取【原文简介】失败*'
            } -Times 1 -Exactly
        }

        It '读取中文简介失败时应抛强类型异常并保留原始异常为 InnerException' {
            Mock Read-MultiLineInput -ModuleName IPAP -ParameterFilter { $Prompt -like '*中文简介*' } {
                throw [System.InvalidOperationException]::new('控制台不可用')
            }

            $caught = $null
            try {
                Get-ProjectBriefInfo -OriginalOverview '已有原文简介'
            }
            catch {
                $caught = $PSItem
            }

            $caught.Exception | Should -BeOfType [System.InvalidOperationException]
            $caught.Exception.Message | Should -BeLike '*读取【中文简介】失败*'
            $caught.Exception.InnerException | Should -BeOfType [System.InvalidOperationException]
            $caught.Exception.InnerException.Message | Should -Be '控制台不可用'
        }
    }

    Context '交互输入与多行简介 - L4 分支覆盖' {
        It '应支持多行原文简介输入（逐行断言）' {
            $script:OriginalOverviewLines = @('First line', 'Second line')
            $script:ChineseOverviewLines = @()

            $Formatted, $ProjectName = Get-ProjectBriefInfo

            # 以标题行定位内容起始行，避免对多行简介的行数偏移做硬编码
            $Lines = $Formatted -split "`n"
            $OriginalIdx = [Array]::IndexOf($Lines, '【原文简介】')
            $ChineseIdx = [Array]::IndexOf($Lines, '【中文简介】')
            $Lines[$OriginalIdx + 1] | Should -BeExactly 'First line'
            $Lines[$OriginalIdx + 2] | Should -BeExactly 'Second line'
            $Lines[$ChineseIdx + 1] | Should -BeExactly ''  # 中文简介为空 → 空行占位
        }

        It '空行应结束多行输入（简介段为空行占位）' {
            $script:OriginalOverviewLines = @()
            $script:ChineseOverviewLines = @()

            $Formatted, $ProjectName = Get-ProjectBriefInfo

            $ProjectName | Should -Be '[TestAuthor] TestProject'
            # 以标题行定位内容起始行，断言两段简介均为空占位
            $Lines = $Formatted -split "`n"
            $OriginalIdx = [Array]::IndexOf($Lines, '【原文简介】')
            $ChineseIdx = [Array]::IndexOf($Lines, '【中文简介】')
            $Lines[$OriginalIdx + 1] | Should -BeExactly ''
            $Lines[$ChineseIdx + 1] | Should -BeExactly ''
        }
    }

    Context '字符串处理 - L3 边界' {
        It '原作品名应去除首尾空格（交互分支 Trim）' {
            $script:OriginalTitle = '  TestProject  '

            $Formatted, $ProjectName = Get-ProjectBriefInfo

            $ProjectName | Should -Be '[TestAuthor] TestProject'
        }

        It '作品中文译名应去除首尾空格（交互分支 Trim）' {
            $script:ChineseTitle = '  测试项目  '

            $Formatted, $ProjectName = Get-ProjectBriefInfo

            ($Formatted -split "`n")[3] | Should -BeExactly '  中文：[TestAuthor] 测试项目'
        }

        It '作者名应去除首尾空格（交互分支 Trim）' {
            $script:AuthorName = '  Author  '

            $Formatted, $ProjectName = Get-ProjectBriefInfo

            $ProjectName | Should -Be '[Author] TestProject'
        }

        It '参数传入的作者名与原作品名应去除首尾空白（非交互分支 Trim）' {
            # ProjectName 的唯一汇合点归一：配置来源（非交互分支）原样传入时也须去空白，
            # 否则返回给 README 的名字与 New-ProjectStructure 实际创建的目录名不一致
            $script:ThrowOnReadHost = $true

            $Formatted, $ProjectName = Get-ProjectBriefInfo `
                -Author '  鲁迅  ' `
                -OriginalTitle '  呐喊  ' `
                -ChineseTitle '呐喊' `
                -OriginalOverview '原文简介内容' `
                -ChineseOverview '中文简介内容'

            $ProjectName | Should -BeExactly '[鲁迅] 呐喊'
            ($Formatted -split "`n")[2] | Should -BeExactly '  原文：[鲁迅] 呐喊'
        }
    }

    Context '返回值格式测试 - L5 输出字段' {
        It '返回格式应包含完整模板结构（全量精确断言）' {
            $Formatted, $ProjectName = Get-ProjectBriefInfo

            $Expected = @(
                '',
                '【项目名称】',
                '  原文：[TestAuthor] TestProject',
                '  中文：[TestAuthor] 中文标题',
                '',
                '【项目简介】',
                '---',
                '【原文简介】',
                "原文简介第一行`n原文简介第二行",
                '---',
                '【中文简介】',
                "中文简介第一行`n中文简介第二行",
                '---',
                ''
            ) -join "`n"

            $Formatted | Should -BeExactly $Expected
        }
    }

    Context '参数化调用测试 - L1/L4 分支' {
        It '传入所有参数时应直接返回格式化结果，不触发交互式输入' {
            $script:ThrowOnReadHost = $true

            $Formatted, $ProjectName = Get-ProjectBriefInfo -Author '鲁迅' -OriginalTitle '呐喊' -ChineseTitle '呐喊' -OriginalOverview '原文简介内容' -ChineseOverview '中文简介内容'

            $ProjectName | Should -Be '[鲁迅] 呐喊'
            ($Formatted -split "`n")[8] | Should -BeExactly '原文简介内容'
            ($Formatted -split "`n")[11] | Should -BeExactly '中文简介内容'
        }

        It '仅传部分参数时应对未传参数触发交互式输入' {
            $script:AuthorName = 'Author'
            $script:OriginalTitle = 'Title'
            $script:ChineseTitle = '中文标题'

            $Formatted, $ProjectName = Get-ProjectBriefInfo -Author 'Author' -OriginalTitle 'Title'

            $ProjectName | Should -Be '[Author] Title'
            $Lines = $Formatted -split "`n"
            $Lines[3] | Should -BeExactly '  中文：[Author] 中文标题'
            # 以标题行定位简介内容起始行
            $OriginalIdx = [Array]::IndexOf($Lines, '【原文简介】')
            $ChineseIdx = [Array]::IndexOf($Lines, '【中文简介】')
            $Lines[$OriginalIdx + 1] | Should -BeExactly '原文简介第一行'
            $Lines[$ChineseIdx + 1] | Should -BeExactly '中文简介第一行'
        }

        It '使用多行简介参数时应正确处理换行符' {
            $script:ThrowOnReadHost = $true

            $Formatted, $ProjectName = Get-ProjectBriefInfo `
                -Author 'Author' `
                -OriginalTitle 'Title' `
                -ChineseTitle '标题' `
                -OriginalOverview "第一行`n第二行`n第三行" `
                -ChineseOverview "中文第一行`n中文第二行"

            # 以标题行定位简介内容起始行，按多行顺序逐行断言
            $Lines = $Formatted -split "`n"
            $OriginalIdx = [Array]::IndexOf($Lines, '【原文简介】')
            $ChineseIdx = [Array]::IndexOf($Lines, '【中文简介】')
            $Lines[$OriginalIdx + 1] | Should -BeExactly '第一行'
            $Lines[$OriginalIdx + 2] | Should -BeExactly '第二行'
            $Lines[$OriginalIdx + 3] | Should -BeExactly '第三行'
            $Lines[$ChineseIdx + 1] | Should -BeExactly '中文第一行'
            $Lines[$ChineseIdx + 2] | Should -BeExactly '中文第二行'
        }

        It '参数为空字符串时应视为未提供，触发交互式输入' {
            $script:AuthorName = '交互式作者'
            $script:OriginalTitle = '交互作品'
            $script:ChineseTitle = '中文标题'

            $Formatted, $ProjectName = Get-ProjectBriefInfo -Author '' -OriginalTitle '' -ChineseTitle ''

            $ProjectName | Should -Be '[交互式作者] 交互作品'
            ($Formatted -split "`n")[2] | Should -BeExactly '  原文：[交互式作者] 交互作品'
        }

        It '参数为空白字符时应视为未提供，触发交互式输入' {
            $script:AuthorName = '交互式作者'
            $script:OriginalTitle = '交互作品'
            $script:ChineseTitle = '中文标题'

            $Formatted, $ProjectName = Get-ProjectBriefInfo -Author '  ' -OriginalTitle '  ' -ChineseTitle '  '

            $ProjectName | Should -Be '[交互式作者] 交互作品'
            ($Formatted -split "`n")[2] | Should -BeExactly '  原文：[交互式作者] 交互作品'
        }
    }

    Context '参数契约验证 - 契约' {
        It '应声明 5 个可选字符串参数（均无 Mandatory）' {
            $Cmd = Get-Command Get-ProjectBriefInfo

            $Cmd.Parameters.Keys | Should -Contain 'Author'
            $Cmd.Parameters.Keys | Should -Contain 'OriginalTitle'
            $Cmd.Parameters.Keys | Should -Contain 'ChineseTitle'
            $Cmd.Parameters.Keys | Should -Contain 'OriginalOverview'
            $Cmd.Parameters.Keys | Should -Contain 'ChineseOverview'
            $Cmd.Parameters.Count | Should -BeGreaterOrEqual 5
        }

        It '应声明 OutputType 为 string' {
            $Cmd = Get-Command Get-ProjectBriefInfo

            @($Cmd.OutputType.Type.Name) | Should -Contain 'String'
        }
    }
}