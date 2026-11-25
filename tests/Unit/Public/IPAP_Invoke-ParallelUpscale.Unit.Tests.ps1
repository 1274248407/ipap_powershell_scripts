#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Invoke-ParallelUpscale 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五级要求编写，测试 Invoke-ParallelUpscale 的函数契约、
    引擎缺失异常、参数边界与并行失败路径计数（Mock 隔离外部依赖，无需真实引擎）：
    - Level1 正常流程：单图成功路径已抽到 Invoke-UpscaleProcess，由其单测覆盖；
      本文件继续验证编排层（失败计数、输出目录、参数契约、返回结构）
    - Level2 异常流程：引擎路径缺失抛 [System.IO.FileNotFoundException] 强类型
      异常（类型级断言 + 消息断言）；参数校验拒绝由引擎绑定抛
      ParameterBindingException 家族（用公共父类型断言，函数体不进入）
    - Level3 边界数据：ValidateRange/ValidateSet 上下界接受与越界拒绝、参数默认值
      （MaxWorkers 默认 8，修复与文档对齐）、Images 数组边界
    - Level4 分支覆盖：Test-Path 输出目录存在/不存在分支（New-Item 是否调用）、
      并行块失败 catch 分支真实计数（& $null 抛错 / & 不存在 exe 抛 CommandNotFound）
    - Level5 输出字段：返回 hashtable、Keys 仅含 SuccessCount/FailedCount、
      失败路径数值精确断言

    测试隔离策略（仅 Mock 外部依赖）：
    - Mock Test-Path / New-Item / Get-RealCuganExePath / Get-FfmpegPath 定义在
      BeforeEach（AGENTS 规范），以 $MockImages / $OutputDirExists 承载用例数据；
    - 禁止 Mock ForEach-Object：Pester 无法定向 Mock ForEach-Object -Parallel
      （无 filter Mock 会连聚合链一并吞掉导致计数从未真实执行；带 filter Mock 时
      返回值不流入下游真实聚合，探针实证）。并行块以真实执行 + 失败路径驱动聚合，
      计数逻辑因此被真实覆盖；
    - 成功路径：Invoke-UpscaleProcess / Get-RealCuganArgument / Get-FfmpegArgument /
      Write-UpscaleSummary 均有独立单测；本文件保留并行编排层的失败路径与契约测试。

.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'Invoke-ParallelUpscale Unit Tests' -Tag 'Invoke-ParallelUpscale', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 屏蔽日志输出（Write-LogEntry 为纯日志函数，全级别静默记录；无状态 Mock）
        Mock Write-LogEntry -ModuleName IPAP { }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '引擎可执行文件缺失处理 - L2 异常流程' {
        BeforeEach {
            $script:MockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock New-Item -ModuleName IPAP { }
        }

        It 'RealCugan 引擎且 Get-RealCuganExePath 找不到时应抛出强类型 FileNotFoundException' {
            Mock Get-RealCuganExePath -ModuleName IPAP {
                throw [System.IO.FileNotFoundException]::new('未找到 Real-CUGAN')
            }

            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException]) -ExpectedMessage '未找到 Real-CUGAN*'
        }

        It 'FFmpeg 引擎且 Get-FfmpegPath 找不到时应抛出强类型 FileNotFoundException' {
            Mock Get-FfmpegPath -ModuleName IPAP {
                throw [System.IO.FileNotFoundException]::new('未找到 FFmpeg')
            }

            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'FFmpeg' } |
                Should -Throw -ExceptionType ([System.IO.FileNotFoundException]) -ExpectedMessage '未找到 FFmpeg*'
        }
    }

    Context '参数契约验证 - 契约验证' {
        It '函数应有 Mandatory 参数 Images' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['Images']
            $Param.Attributes.Mandatory | Should -Be $true
        }

        It '函数应有 Mandatory 参数 OutputDir' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['OutputDir']
            $Param.Attributes.Mandatory | Should -Be $true
        }

        It 'MaxWorkers 参数应使用 ValidateRange(1, 32)' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['MaxWorkers']
            $RangeAttr = $Param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateRangeAttribute' }

            $RangeAttr.MinRange | Should -Be 1
            $RangeAttr.MaxRange | Should -Be 32
        }

        It 'Scale 参数应使用 ValidateRange(1, 4)' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['Scale']
            $RangeAttr = $Param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateRangeAttribute' }

            $RangeAttr.MinRange | Should -Be 1
            $RangeAttr.MaxRange | Should -Be 4
        }

        It 'NoiseLevel 参数应使用 ValidateRange(-1, 3)' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['NoiseLevel']
            $RangeAttr = $Param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateRangeAttribute' }

            $RangeAttr.MinRange | Should -Be -1
            $RangeAttr.MaxRange | Should -Be 3
        }

        It 'TileSize 参数应使用 ValidateRange(32, 1024)' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['TileSize']
            $RangeAttr = $Param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateRangeAttribute' }

            $RangeAttr.MinRange | Should -Be 32
            $RangeAttr.MaxRange | Should -Be 1024
        }

        It 'ModelPath 参数应使用 ValidateSet' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['ModelPath']
            $SetAttr = $Param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateSetAttribute' }

            $SetAttr.ValidValues | Should -Contain 'models-se'
            $SetAttr.ValidValues | Should -Contain 'models-pro'
            $SetAttr.ValidValues | Should -Contain 'models-nose'
        }

        It 'OutputFormat 参数应使用 ValidateSet' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['OutputFormat']
            $SetAttr = $Param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateSetAttribute' }

            $SetAttr.ValidValues | Should -Contain 'jpg'
            $SetAttr.ValidValues | Should -Contain 'png'
            $SetAttr.ValidValues | Should -Contain 'webp'
        }

        It '函数应声明 OutputType 为 hashtable' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            @($Cmd.OutputType.Type.Name) | Should -Contain 'Hashtable'
        }

        It 'Engine 参数应使用 ValidateSet 且包含 RealCugan / FFmpeg / Webp' {
            $Cmd = Get-Command Invoke-ParallelUpscale
            $Param = $Cmd.Parameters['Engine']
            $SetAttr = $Param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateSetAttribute' }

            $SetAttr.ValidValues | Should -Contain 'RealCugan'
            $SetAttr.ValidValues | Should -Contain 'FFmpeg'
            $SetAttr.ValidValues | Should -Contain 'Webp'
        }
    }

    Context 'Webp 转码引擎 - L1/L2/L4' {
        BeforeEach {
            $script:MockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock New-Item -ModuleName IPAP { }
            Mock Get-FfmpegPath -ModuleName IPAP { return $null }
        }

        It 'Engine Webp 应以 -NoResize 与 webp 输出格式调用 Get-FfmpegArgument' {
            Mock Get-FfmpegArgument -ModuleName IPAP { return @('-i', 'C:\test1.jpg', '-y', 'C:\output\test1.webp') }

            $null = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'Webp' -MaxWorkers 1

            Should -Invoke -ModuleName IPAP Get-FfmpegArgument -Times 1 -Exactly `
                -ParameterFilter { [bool]$NoResize -eq $true -and $OutputFormat -eq 'webp' }
        }

        It 'Engine FFmpeg 不应带 -NoResize' {
            Mock Get-FfmpegArgument -ModuleName IPAP { return @('-i', 'C:\test1.jpg', '-y', 'C:\output\test1.webp') }

            $null = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'FFmpeg' -MaxWorkers 1

            Should -Invoke -ModuleName IPAP Get-FfmpegArgument -Times 1 -Exactly `
                -ParameterFilter { [bool]$NoResize -eq $false }
        }

        It 'Quality 应传给 Get-FfmpegArgument（Webp 与 FFmpeg 两条路径）' {
            Mock Get-FfmpegArgument -ModuleName IPAP { return @('-i', 'C:\test1.jpg', '-y', 'C:\output\test1.webp') }

            $null = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'Webp' -MaxWorkers 1 -Quality 80
            $null = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'FFmpeg' -MaxWorkers 1 -Quality 80

            Should -Invoke -ModuleName IPAP Get-FfmpegArgument -Times 2 -Exactly `
                -ParameterFilter { $Quality -eq 80 }
        }

        It 'Quality 超出 0-100 时应被 ValidateRange 拒绝' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'Webp' -Quality 101 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'Engine Webp 搭配非 webp 输出格式时应抛 ArgumentException' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'Webp' -OutputFormat 'jpg' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "*只能配合*webp*"
        }

        It 'Engine Webp 搭配 jpg 时应记录一次 Error 日志' {
            $script:Caught = $null
            try {
                Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'Webp' -OutputFormat 'png'
            }
            catch {
                $script:Caught = $PSItem
            }

            $script:Caught | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName IPAP Write-LogEntry -Times 1 -Exactly `
                -ParameterFilter { $Level -eq 'Error' -and $Message -like '*只能配合*' }
        }

        It 'Engine Webp 时 exe 缺失应计入失败计数（不做静默成功）' {
            $Result = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'Webp' -MaxWorkers 1

            $Result.SuccessCount | Should -Be 0
            $Result.FailedCount  | Should -Be 1
        }
    }

    Context '参数行为测试 - L3 边界数据' {
        BeforeEach {
            $script:MockImages = @(
                [PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' }
            )
            Mock Get-RealCuganExePath -ModuleName IPAP { return 'C:\bin\realcugan-ncnn-vulkan.exe' }
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock New-Item -ModuleName IPAP { }
            # 参数接受值用例只关注绑定不抛错，Mock ForEach-Object 吞掉并行块与聚合链
            # （不验证计数，计数由"并行失败路径计数"Context 真实驱动）
            Mock ForEach-Object -ModuleName IPAP { return @{ Success = $true; Image = 'test.jpg' } }
        }

        It 'Scale 参数应接受边界值 1' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -Scale 1 } | Should -Not -Throw
        }

        It 'Scale 参数应接受边界值 4' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -Scale 4 } | Should -Not -Throw
        }

        It 'Scale 参数应拒绝小于 1 的值（ParameterBindingException 家族）' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -Scale 0 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'Scale 参数应拒绝大于 4 的值（ParameterBindingException 家族）' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -Scale 5 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'NoiseLevel 参数应接受边界值 -1' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -NoiseLevel -1 } | Should -Not -Throw
        }

        It 'NoiseLevel 参数应接受边界值 3' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -NoiseLevel 3 } | Should -Not -Throw
        }

        It 'NoiseLevel 参数应拒绝小于 -1 的值（ParameterBindingException 家族）' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -NoiseLevel -2 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'NoiseLevel 参数应拒绝大于 3 的值（ParameterBindingException 家族）' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -NoiseLevel 4 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'TileSize 参数应接受边界值 32' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -TileSize 32 } | Should -Not -Throw
        }

        It 'TileSize 参数应接受边界值 1024' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -TileSize 1024 } | Should -Not -Throw
        }

        It 'TileSize 参数应拒绝小于 32 的值（ParameterBindingException 家族）' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -TileSize 31 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'MaxWorkers 参数应接受边界值 1' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 } | Should -Not -Throw
        }

        It 'MaxWorkers 参数应接受边界值 32' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 32 } | Should -Not -Throw
        }

        It 'MaxWorkers 参数应拒绝小于 1 的值（ParameterBindingException 家族）' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 0 } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'ModelPath 参数应接受有效值 models-se' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -ModelPath 'models-se' } | Should -Not -Throw
        }

        It 'ModelPath 参数应接受有效值 models-pro' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -ModelPath 'models-pro' } | Should -Not -Throw
        }

        It 'ModelPath 参数应接受有效值 models-nose' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -ModelPath 'models-nose' } | Should -Not -Throw
        }

        It 'ModelPath 参数应拒绝无效值（ParameterBindingException 家族）' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -ModelPath 'invalid-model' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }

        It 'OutputFormat 参数应接受有效值 jpg' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -OutputFormat 'jpg' } | Should -Not -Throw
        }

        It 'OutputFormat 参数应接受有效值 png' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -OutputFormat 'png' } | Should -Not -Throw
        }

        It 'OutputFormat 参数应接受有效值 webp' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -OutputFormat 'webp' } | Should -Not -Throw
        }

        It 'OutputFormat 参数应拒绝无效值（ParameterBindingException 家族）' {
            { Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1 -OutputFormat 'gif' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }
    }

    Context '输出目录处理 - L4 分支覆盖' {
        BeforeEach {
            $script:MockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )
            $script:OutputDirExists = $true
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' {
                return $script:OutputDirExists
            }
            Mock New-Item -ModuleName IPAP { }
            Mock Get-RealCuganExePath -ModuleName IPAP { return $null }
        }

        It '输出目录不存在时应创建（New-Item 调用 1 次）' {
            $script:OutputDirExists = $false

            Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1

            Should -Invoke -ModuleName IPAP New-Item -Times 1
        }

        It '输出目录已存在时不应创建（New-Item 调用 0 次）' {
            Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1

            Should -Invoke -ModuleName IPAP New-Item -Times 0
        }
    }

    Context '并行失败路径计数 - L1/L4 聚合计数 + L5 输出字段' {
        BeforeEach {
            $script:MockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )
            Mock Get-RealCuganExePath -ModuleName IPAP { return $null }
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock New-Item -ModuleName IPAP { }
            # 不 Mock ForEach-Object：并行块真实执行，失败路径真实驱动聚合计数
        }

        It 'exe 路径为空时单张图片应真实计入失败计数（FailedCount=1）' {
            $Result = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1

            $Result.SuccessCount | Should -Be 0
            $Result.FailedCount  | Should -Be 1
        }

        It 'exe 路径为空时多张图片应逐一计入失败计数（FailedCount=2）' {
            $script:MockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' },
                [PSCustomObject]@{ Name = 'test2.jpg'; FullName = 'C:\test2.jpg' }
            )

            $Result = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 2

            $Result.SuccessCount | Should -Be 0
            $Result.FailedCount  | Should -Be 2
        }

        It 'exe 路径不存在时（& 调用抛 CommandNotFound）应计入失败计数（FailedCount=1）' {
            Mock Get-RealCuganExePath -ModuleName IPAP { return 'C:\nope\missing.exe' }

            $Result = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1

            $Result.SuccessCount | Should -Be 0
            $Result.FailedCount  | Should -Be 1
        }

        It 'FFmpeg 引擎应走 Get-FfmpegArgument 参数拼装分支并计入失败计数' {
            Mock Get-FfmpegPath -ModuleName IPAP { return $null }

            $Result = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -Engine 'FFmpeg' -MaxWorkers 1

            $Result.SuccessCount | Should -Be 0
            $Result.FailedCount  | Should -Be 1
        }

        It '应返回包含 SuccessCount 和 FailedCount 的哈希表（Keys 精确）' {
            $Result = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output' -MaxWorkers 1

            $Result | Should -BeOfType [hashtable]
            @($Result.Keys).Count | Should -Be 2
            $Result.Keys | Should -Contain 'SuccessCount'
            $Result.Keys | Should -Contain 'FailedCount'
        }

        It '带空格的路径应正确处理（失败路径计数不受影响）' {
            $script:MockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\Program Files\test1.jpg' }
            )

            $Result = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\Program Files\output' -MaxWorkers 1

            $Result | Should -Not -BeNullOrEmpty
            $Result.Keys | Should -Contain 'SuccessCount'
            $Result.Keys | Should -Contain 'FailedCount'
        }
    }

    Context '参数默认值 - L3 边界数据' {
        BeforeEach {
            $script:MockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )
            Mock Get-RealCuganExePath -ModuleName IPAP { return $null }
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock New-Item -ModuleName IPAP { }
        }

        It '源码 MaxWorkers 默认值应为 8（AST 契约，与文档/ValidateRange 对齐）' {
            # 源码默认值 0 曾与 [ValidateRange(1,32)]/文档"默认 8"冲突，已修复为 8；
            # 此处以 AST 解析 param 块默认值做契约级断言（Get-Command 不暴露默认值）
            $SourcePath = Join-Path $ProjectRoot 'source\Public\Invoke-ParallelUpscale.ps1'
            $AstTokens = $null
            $AstErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($SourcePath, [ref]$AstTokens, [ref]$AstErrors)
            $Fn = $Ast.Find({ param($Node) $Node.Name -eq 'Invoke-ParallelUpscale' }, $true)
            $MaxWorkersParam = $Fn.Body.ParamBlock.Parameters | Where-Object { $PSItem.Name.VariablePath.UserPath -eq 'MaxWorkers' }

            $MaxWorkersParam.DefaultValue.Extent.Text | Should -Be '8'
        }

        It '不传 MaxWorkers 时默认调用应正常执行（不再被参数校验拒绝）' {
            # 修复前默认值 0 虽不被 ValidateRange 拦截，但会以 ThrottleLimit=0 进入并行块；
            # 修复为 8 后默认调用完整执行真实并行失败路径
            $Result = Invoke-ParallelUpscale -Images $script:MockImages -OutputDir 'C:\output'

            $Result.SuccessCount | Should -Be 0
            $Result.FailedCount  | Should -Be 1
        }
    }
}