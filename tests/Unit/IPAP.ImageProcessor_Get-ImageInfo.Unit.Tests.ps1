#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Get-ImageInfo 单元测试
.DESCRIPTION
    测试 Get-ImageInfo 函数的图片目录分析和统计功能。
    测试图片准备清单：tests/data/images/ 目录下的图片文件。
#>

Describe 'Get-ImageInfo Unit Tests' -Tag 'Get-ImageInfo', 'IPAP.ImageProcessor' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        
        # 先导入依赖的 IPAP.Core 模块
        $CoreModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psd1'
        if (Test-Path $CoreModulePath)
        {
            Import-Module $CoreModulePath -Force -Global
        }
        
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        # 初始化全局变量
        $Global:SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff')

        # 使用全局 Mock
        Mock Write-InfoLog -ModuleName IPAP.ImageProcessor {}
        Mock Write-ErrorLog -ModuleName IPAP.ImageProcessor {}
        Mock Get-NaturalSortKey -ModuleName IPAP.Core { param($String) return @($String) }
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '源目录存在图片文件时应返回图片信息' {
            # 当 Mock 带有复杂参数集的 cmdlet（如 Get-ChildItem 、 Test-Path ）时，Pester 无法正确解析参数绑定，导致参数集冲突。
            # 使用 -RemoveParameterType 参数可以移除参数类型约束
            Mock Test-Path -ModuleName IPAP.ImageProcessor -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor -RemoveParameterType 'Path', 'LiteralPath' {
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor -RemoveParameterType 'Path', 'LiteralPath' {
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor -RemoveParameterType 'Path', 'LiteralPath' {
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor -RemoveParameterType 'Path', 'LiteralPath' {
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor { param($LiteralPath) return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor { param($LiteralPath)
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor { param($LiteralPath) return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor { param($LiteralPath)
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor { param($LiteralPath) return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor { param($LiteralPath) return @() }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            $result.AverageSize | Should -Be 0
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
