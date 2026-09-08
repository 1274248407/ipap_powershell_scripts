#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-ImageInfo 单元测试
.DESCRIPTION
    测试 Get-ImageInfo 函数的图片目录分析和统计功能。
    测试图片准备清单：tests/data/images/ 目录下的图片文件。
#>

Describe 'Get-ImageInfo Unit Tests' -Tag 'Get-ImageInfo', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 初始化全局配置实例（Get-ImageInfo 从此读取支持的图片格式）
        $Global:IPAPConfigInstance = @{
            App = @{
                SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff')
            }
        }

        # 使用全局 Mock（Write-ErrorLog 模拟真实 throw 语义）
        Mock Write-InfoLog -ModuleName IPAP {}
        Mock Write-WarningLog -ModuleName IPAP {}
        Mock Write-ErrorLog -ModuleName IPAP { param($Message) throw $Message }
        Mock Get-NaturalSortKey -ModuleName IPAP { param($String) return @($String) }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '源目录存在图片文件时应返回图片信息' {
            # 当 Mock 带有复杂参数集的 cmdlet（如 Get-ChildItem 、 Test-Path ）时，Pester 无法正确解析参数绑定，导致参数集冲突。
            # 使用 -RemoveParameterType 参数可以移除参数类型约束
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock Get-ChildItem -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' {
                return @(
                    [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg'; Length = 1024 },
                    [PSCustomObject]@{ Name = 'test2.jpg'; Extension = '.jpg'; Length = 2048 }
                )
            }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            $result | Should -Not -BeNullOrEmpty
            $result.Images | Should -Not -BeNullOrEmpty
        }

        It '应返回正确的哈希表结构' {
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock Get-ChildItem -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' {
                return @(
                    [PSCustomObject]@{ Name = 'test.jpg'; Extension = '.jpg'; Length = 1024 }
                )
            }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            $result.Keys | Should -Contain 'Images'
            $result.Keys | Should -Contain 'TotalSize'
            $result.Keys | Should -Contain 'AverageSize'
            $result.Keys | Should -Contain 'Count'
        }

        It '应正确计算图片数量' {
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock Get-ChildItem -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' {
                return @(
                    [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg'; Length = 1024 },
                    [PSCustomObject]@{ Name = 'test2.jpg'; Extension = '.jpg'; Length = 2048 },
                    [PSCustomObject]@{ Name = 'test3.jpg'; Extension = '.jpg'; Length = 3072 }
                )
            }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            $result.Count | Should -Be 3
        }
    }

    Context '图片格式过滤测试 - Image Format Filtering' {
        It '应只包含支持的图片格式' {
            Mock Test-Path -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock Get-ChildItem -ModuleName IPAP -RemoveParameterType 'Path', 'LiteralPath' {
                return @(
                    [PSCustomObject]@{ Name = 'test.jpg'; Extension = '.jpg'; Length = 1024 },
                    [PSCustomObject]@{ Name = 'test.png'; Extension = '.png'; Length = 2048 },
                    [PSCustomObject]@{ Name = 'test.txt'; Extension = '.txt'; Length = 100 },
                    [PSCustomObject]@{ Name = 'test.webp'; Extension = '.webp'; Length = 512 }
                )
            }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            $result.Images.Count | Should -Be 3
            $result.Count | Should -Be 3
        }

        It '应支持 WebP 格式' {
            Mock Test-Path -ModuleName IPAP { param($LiteralPath) return $true }
            Mock Get-ChildItem -ModuleName IPAP { param($LiteralPath)
                return @(
                    [PSCustomObject]@{ Name = 'test.webp'; Extension = '.webp'; Length = 1024 }
                )
            }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            $result.Count | Should -Be 1
        }
    }

    Context '平均大小计算测试 - Average Size Calculation' {
        It '应正确计算平均大小' {
            Mock Test-Path -ModuleName IPAP { param($LiteralPath) return $true }
            Mock Get-ChildItem -ModuleName IPAP { param($LiteralPath)
                return @(
                    [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg'; Length = 1024 },
                    [PSCustomObject]@{ Name = 'test2.jpg'; Extension = '.jpg'; Length = 2048 }
                )
            }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            # 计算公式：(1024 + 2048) / 1024 / 2 = 3072 / 1024 / 2 = 1.5
            $result.AverageSize | Should -Be 1.5
        }

        It '空目录平均大小应为 0' {
            Mock Test-Path -ModuleName IPAP { param($LiteralPath) return $true }
            Mock Get-ChildItem -ModuleName IPAP { param($LiteralPath) return @() }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            $result.AverageSize | Should -Be 0
        }
    }

    Context '失败路径测试 - Failure Path' {
        It '源目录不存在时应抛出终止错误' {
            { Get-ImageInfo -SourceDir 'Z:\不存在' } | Should -Throw '源目录不存在*'
        }
    }

    Context '必填参数测试 - Mandatory Parameter' {
        It '函数应有 Mandatory 参数 SourceDir' {
            $cmd = Get-Command Get-ImageInfo
            $sourceDirParam = $cmd.Parameters['SourceDir']
            $sourceDirParam.Attributes.Mandatory | Should -Be $true
        }
    }
}
