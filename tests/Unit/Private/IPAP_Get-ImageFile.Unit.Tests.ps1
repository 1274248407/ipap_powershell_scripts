#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ImageFile 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 五级要求编写，测试 Get-ImageFile（Private，未导出）
    的目录扫描与格式过滤组合行为：
    - Level1 正常流程：混合格式过滤、SupportedFormats 缺省委托配置、显式格式覆盖配置
    - Level2 异常流程：本函数无自定义逻辑异常分支（源码无守卫、无 try-catch），
      L2 以 Mandatory 参数引擎校验承载；路径不存在由调用方 Select-NonTextImage 先行
      Test-Path 保障（源码 :48），详见"源码缺口说明"。
    - Level3 边界数据：空目录、0 字节文件、扩展名大小写、无扩展名文件、全不支持格式目录
    - Level4 分支覆盖：LiteralPath 传参、-File 模式、非递归、SupportedFormats 两条分支
      （显式传入 / null 委托配置 / 空数组委托配置）
    - Level5 输出字段：透传元素 Name/Extension/Length 逐字段验证、原始顺序保持（不排序）

    测试隔离策略（仅 Mock 外部依赖）：
    - Mock Get-ChildItem（外部 cmdlet）定义在 BeforeEach（AGENTS 规范），每个测试前
      重新定义、以 $script:FixtureFiles 承载各用例数据，避免测试间共享状态；
    - 真实调用模块内 Test-SupportedImageFormat（格式判定已有独立单测，此处验证组合契约）；
    - 缺省委托分支所需配置通过 InModuleScope 注入 $script:IPAPConfigInstance
      （hashtable 先例，与 Get-ImageInfo 单测一致）。
    - Mock 返回 PSCustomObject 形状（Name/Extension/Length），验证字段透传；
      真实 System.IO.FileInfo 产出属 Get-ChildItem 原生行为，单元层不重复验证类型。

    源码缺口说明（Q2=A 决策：本次不改源码，仅记录）：
    - Get-ImageFile 无 Test-Path 守卫、无 try-catch，不满足 AGENTS"IO 必须包裹
      try-catch"；路径不存在时由 Get-ChildItem 抛非终止错误，不在单元测试中构造该
      场景（Mock 层无法复现非终止错误语义），源码整改留作独立任务。

.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

Describe 'Get-ImageFile Unit Tests' -Tag 'Get-ImageFile', 'IPAP' {
    BeforeAll {
        # tests\Unit\Private → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 注入配置实例（Test-SupportedImageFormat 缺省委托分支读取默认格式列表）
        InModuleScope IPAP {
            $script:IPAPConfigInstance = @{
                App = @{
                    SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff')
                }
            }
        }

        # 屏蔽日志输出（无状态 Mock：真实调用 Test-SupportedImageFormat 的可能路径）
        Mock Write-LogEntry -ModuleName IPAP { }
    }

    BeforeEach {
        # AGENTS 规范：Mock 定义在 BeforeEach，每个测试前重新定义，避免状态污染。
        # Mock 脚本块延迟求值，返回 $script:FixtureFiles（各 It 在调用前设置数据）。
        $script:FixtureFiles = @()
        $script:CapturedPath = $null
        $script:FileSwitchPassed = $false
        $script:RecursePassed = $false
        Mock Get-ChildItem -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' {
            param($LiteralPath, [switch]$File, [switch]$Recurse)
            $script:CapturedPath = $LiteralPath
            $script:FileSwitchPassed = $PSBoundParameters.ContainsKey('File')
            $script:RecursePassed = $PSBoundParameters.ContainsKey('Recurse')
            return $script:FixtureFiles
        }
    }

    AfterAll {
        InModuleScope IPAP { $script:IPAPConfigInstance = $null }
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - L1 正常流程' {
        It '应过滤掉不支持的格式，只返回支持的图片文件' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg'; Length = 1024 },
                [PSCustomObject]@{ Name = 'test2.png'; Extension = '.png'; Length = 2048 },
                [PSCustomObject]@{ Name = 'note.txt'; Extension = '.txt'; Length = 500 }
            )

            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            @($result).Count | Should -Be 2
            @($result).Name | Should -Contain 'test1.jpg'
            @($result).Name | Should -Contain 'test2.png'
            @($result).Name | Should -Not -Contain 'note.txt'
        }

        It 'SupportedFormats 缺省（null）时应委托配置默认格式列表' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'a.jpg'; Extension = '.jpg'; Length = 1024 },
                [PSCustomObject]@{ Name = 'b.webp'; Extension = '.webp'; Length = 2048 },
                [PSCustomObject]@{ Name = 'c.gif'; Extension = '.gif'; Length = 300 },
                [PSCustomObject]@{ Name = 'd.txt'; Extension = '.txt'; Length = 100 }
            )

            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            # 配置默认格式包含 .jpg/.webp/.gif，.txt 被过滤
            @($result).Count | Should -Be 3
        }

        It '显式 SupportedFormats 应覆盖配置默认格式' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'a.jpg'; Extension = '.jpg'; Length = 1024 },
                [PSCustomObject]@{ Name = 'b.png'; Extension = '.png'; Length = 2048 },
                [PSCustomObject]@{ Name = 'c.tiff'; Extension = '.tiff'; Length = 300 }
            )

            $result = InModuleScope IPAP {
                Get-ImageFile -Path 'C:\images' -SupportedFormats @('.png')
            }

            # 仅 .png 在显式列表内
            @($result).Count | Should -Be 1
            @($result)[0].Name | Should -Be 'b.png'
        }
    }

    Context '异常与参数契约 - L2 异常流程' {
        # L2 说明：本函数无自定义逻辑异常分支（源码无守卫、无 try-catch，Q2=A 决策不改源码），
        # 路径不存在由调用方 Select-NonTextImage 先行 Test-Path 保障（源码 :48）。
        # 此处以 Mandatory 参数引擎校验承载 L2；不设路径不存在的占位用例
        #（Mock 层无法复现非终止错误语义，该场景与函数职责无关）。
        It '函数应声明 Mandatory 参数 Path（InModuleScope 下验证）' {
            InModuleScope IPAP {
                $cmd = Get-Command Get-ImageFile
                $pathParam = $cmd.Parameters['Path']
                $pathParam.Attributes.Mandatory | Should -Be $true
            }
        }

        It 'SupportedFormats 应为可选参数（Mandatory = $false）' {
            InModuleScope IPAP {
                $cmd = Get-Command Get-ImageFile
                $formatsParam = $cmd.Parameters['SupportedFormats']
                @($formatsParam.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }).Mandatory |
                    Should -Be $false
            }
        }
    }

    Context '边界数据 - L3 边界' {
        It '空目录应返回空结果' {
            # $script:FixtureFiles 默认为 @()，无需额外设置
            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            @($result).Count | Should -Be 0
        }

        It '0 字节文件应被包含在结果中' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'empty.jpg'; Extension = '.jpg'; Length = 0 }
            )

            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            @($result).Count | Should -Be 1
            @($result)[0].Length | Should -Be 0
        }

        It '扩展名大小写不敏感（.JPG 应被识别）' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'PHOTO.JPG'; Extension = '.JPG'; Length = 1024 }
            )

            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            @($result).Count | Should -Be 1
            @($result)[0].Name | Should -Be 'PHOTO.JPG'
        }

        It '无扩展名文件应被过滤' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'README'; Extension = ''; Length = 100 }
            )

            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            @($result).Count | Should -Be 0
        }

        It '全为不支持格式时应返回空结果' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'a.txt'; Extension = '.txt'; Length = 100 },
                [PSCustomObject]@{ Name = 'b.doc'; Extension = '.doc'; Length = 200 }
            )

            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            @($result).Count | Should -Be 0
        }
    }

    Context '分支与传参透传 - L4 分支覆盖' {
        It '应以 LiteralPath 传参并以 -File 模式调用 Get-ChildItem' {
            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' | Out-Null }

            $script:CapturedPath | Should -Be 'C:\images'
            $script:FileSwitchPassed | Should -Be $true
            $script:RecursePassed | Should -Be $false -Because 'Get-ImageFile 仅顶层扫描，不递归'
        }

        It 'SupportedFormats 为空数组（@()）时应委托配置默认格式（L4 参数分支）' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'a.jpg'; Extension = '.jpg'; Length = 1024 },
                [PSCustomObject]@{ Name = 'b.png'; Extension = '.png'; Length = 2048 }
            )

            $result = InModuleScope IPAP {
                Get-ImageFile -Path 'C:\images' -SupportedFormats @()
            }

            # 空数组转布尔为 $false，Test-SupportedImageFormat 内 -not 走配置默认
            @($result).Count | Should -Be 2
        }
    }

    Context '输出字段验证 - L5 输出字段' {
        It '应透传元素并保持 Get-ChildItem 原始输出顺序（不排序）' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'b.png'; Extension = '.png'; Length = 2048 },
                [PSCustomObject]@{ Name = 'a.jpg'; Extension = '.jpg'; Length = 1024 }
            )

            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            @($result)[0].Name | Should -Be 'b.png'
            @($result)[1].Name | Should -Be 'a.jpg'
        }

        It '输出元素应完整透传 Name/Extension/Length 字段（L5 逐字段验证）' {
            $script:FixtureFiles = @(
                [PSCustomObject]@{ Name = 'sunset.jpg'; Extension = '.jpg'; Length = 4096 }
            )

            $result = InModuleScope IPAP { Get-ImageFile -Path 'C:\images' }

            $item = @($result)[0]
            $item.Name | Should -Be 'sunset.jpg'
            $item.Extension | Should -Be '.jpg'
            $item.Length | Should -Be 4096
        }
    }
}