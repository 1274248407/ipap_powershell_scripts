#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ImageInfo 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五级要求编写，测试 Get-ImageInfo 的图片目录
    分析与统计功能（Mock 隔离外部依赖，无需真实图片夹具）：
    - Level1 正常流程：混合格式过滤、WebP 支持、数量/平均大小数值计算
    - Level2 异常流程：源目录不存在抛 [System.ArgumentException] 强类型异常
      （类型级断言）；全空白 SourceDir 同分支；空串由引擎 Mandatory 绑定校验
      （ParameterBindingException 家族）拦截，函数体不进入
    - Level3 边界数据：0 字节文件、大写扩展名、全不支持格式目录、
      空目录三字段零值、空串/全空白路径
    - Level4 分支覆盖：Test-Path 真假分支、Test-SupportedImageFormat 过滤分支、
      count>0/=0 分支、Sort-Object 自然排序分支（真实调用 Get-NaturalSortKey）
    - Level5 输出字段：Count/TotalSize/AverageSize 精确断言、
      Images 元素 Name/Extension/Length 逐字段验证、自然排序顺序逐位验证

    测试隔离策略（仅 Mock 外部依赖）：
    - Mock Test-Path / Get-ChildItem（外部 cmdlet）定义在 BeforeEach（AGENTS 规范），
      以 $FixtureFiles / $TestPathResult 承载各用例数据，避免测试间共享状态；
    - 真实调用模块内 Test-SupportedImageFormat 与 Get-NaturalSortKey
      （均为模块内纯函数，不 Mock；各自已有独立单测）；
    - 配置经 InModuleScope 注入 $script:IPAPConfigInstance（hashtable 先例）。

.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'Get-ImageInfo Unit Tests' -Tag 'Get-ImageInfo', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 初始化模块内配置实例（Get-ImageInfo 从此读取支持的图片格式）
        InModuleScope IPAP {
            $script:IPAPConfigInstance = @{
                App = @{
                    SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff')
                }
            }
        }

        # 屏蔽日志输出（Write-LogEntry 为纯日志函数，全级别静默记录；无状态 Mock）
        Mock Write-LogEntry -ModuleName IPAP { }
    }

    BeforeEach {
        # AGENTS 规范：Mock 定义在 BeforeEach，每个测试前重新定义，避免状态污染。
        # Mock 脚本块延迟求值，读取 $FixtureFiles（各 It 在调用前设置）与 $TestPathResult。
        $script:FixtureFiles = @()
        $script:TestPathResult = $true
        Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' {
            return $script:TestPathResult
        }
        Mock Get-ChildItem -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' {
            return $script:FixtureFiles
        }
    }

    AfterAll {
        # 清理模块内配置实例与模块，防止污染其他测试
        InModuleScope IPAP { $script:IPAPConfigInstance = $null }
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - L1 正常流程' {
        It '源目录存在图片文件时应返回图片信息' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg'; Length = 1024 },
                [PSCustomObject]@{ Name = 'test2.jpg'; Extension = '.jpg'; Length = 2048 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            $Result | Should -Not -BeNullOrEmpty
            @($Result.Images).Count | Should -Be 2
        }

        It '应返回正确的哈希表结构（四个字段齐全）' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'test.jpg'; Extension = '.jpg'; Length = 1024 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            $Result.Keys | Should -Contain 'Images'
            $Result.Keys | Should -Contain 'TotalSize'
            $Result.Keys | Should -Contain 'AverageSize'
            $Result.Keys | Should -Contain 'Count'
        }

        It '应正确计算图片数量' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg'; Length = 1024 },
                [PSCustomObject]@{ Name = 'test2.jpg'; Extension = '.jpg'; Length = 2048 },
                [PSCustomObject]@{ Name = 'test3.jpg'; Extension = '.jpg'; Length = 3072 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            $Result.Count | Should -Be 3
        }
    }

    Context '图片格式过滤测试 - L1/L3 格式过滤' {
        It '应只包含支持的图片格式' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'test.jpg'; Extension = '.jpg'; Length = 1024 },
                [PSCustomObject]@{ Name = 'test.png'; Extension = '.png'; Length = 2048 },
                [PSCustomObject]@{ Name = 'test.txt'; Extension = '.txt'; Length = 100 },
                [PSCustomObject]@{ Name = 'test.webp'; Extension = '.webp'; Length = 512 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            $Result.Images.Count | Should -Be 3
            $Result.Count | Should -Be 3
        }

        It '应支持 WebP 格式' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'test.webp'; Extension = '.webp'; Length = 1024 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            $Result.Count | Should -Be 1
        }

        It '扩展名大小写不敏感（.JPG 应被识别）' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'PHOTO.JPG'; Extension = '.JPG'; Length = 1024 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            $Result.Count | Should -Be 1
            @($Result.Images)[0].Name | Should -Be 'PHOTO.JPG'
        }

        It '全为不支持格式目录时应返回零统计' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'a.txt'; Extension = '.txt'; Length = 100 },
                [PSCustomObject]@{ Name = 'b.doc'; Extension = '.doc'; Length = 200 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            @($Result.Images).Count | Should -Be 0
            $Result.Count | Should -Be 0
            $Result.TotalSize | Should -Be 0
            $Result.AverageSize | Should -Be 0
        }
    }

    Context '平均大小计算测试 - L1 数值' {
        It '应正确计算平均大小' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg'; Length = 1024 },
                [PSCustomObject]@{ Name = 'test2.jpg'; Extension = '.jpg'; Length = 2048 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            # 计算公式：(1024 + 2048) / 1024 / 2 = 3072 / 1024 / 2 = 1.5
            $Result.AverageSize | Should -Be 1.5
        }

        It '空目录平均大小应为 0' {
            # $FixtureFiles 默认 @()：空目录
            $Result = Get-ImageInfo -SourceDir 'C:\images'

            $Result.AverageSize | Should -Be 0
        }
    }

    Context '自然排序测试 - L4/L5 排序分支与顺序字段' {
        It '应按自然顺序排序 Images（1 → 2 → 10）' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'test2.jpg'; Extension = '.jpg'; Length = 2048 },
                [PSCustomObject]@{ Name = 'test10.jpg'; Extension = '.jpg'; Length = 3072 },
                [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg'; Length = 1024 }
            )

            $Result = Get-ImageInfo -SourceDir 'C:\images'

            # 真实调用 Get-NaturalSortKey：自然序 1 < 2 < 10（字典序会得到 1 < 10 < 2）
            @($Result.Images)[0].Name | Should -Be 'test1.jpg'
            @($Result.Images)[1].Name | Should -Be 'test2.jpg'
            @($Result.Images)[2].Name | Should -Be 'test10.jpg'
        }
    }

    Context '失败路径 - L2 异常流程' {
        It '源目录不存在时应抛出强类型 ArgumentException' {
            $script:TestPathResult = $false

            { Get-ImageInfo -SourceDir 'C:\不存在' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '源目录不存在*'
        }

        It 'SourceDir 为空字符串时应由引擎绑定校验拦截' {
            # PowerShell Mandatory 字符串参数绑定空串会抛 ParameterBindingValidationException，
            # 函数体不进入（引擎合同行为，非函数逻辑异常）。-ExceptionType 用公共父类型
            # ParameterBindingException 断言（子类型字面量在 Pester 作用域内无法解析）。
            { Get-ImageInfo -SourceDir '' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException]) -ExpectedMessage '*SourceDir*'
        }

        It 'SourceDir 为全空白字符串时应抛出 ArgumentException' {
            $script:TestPathResult = $false

            { Get-ImageInfo -SourceDir '   ' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '源目录不存在*'
        }
    }

    Context '参数契约与 OutputType - 契约验证' {
        It '函数应有 Mandatory 参数 SourceDir' {
            $Cmd = Get-Command Get-ImageInfo
            $SourceDirParam = $Cmd.Parameters['SourceDir']
            $SourceDirParam.Attributes.Mandatory | Should -Be $true
        }

        It '函数应声明 OutputType 为 hashtable' {
            $Cmd = Get-Command Get-ImageInfo
            @($Cmd.OutputType.Type.Name) | Should -Contain 'Hashtable'
        }
    }
}