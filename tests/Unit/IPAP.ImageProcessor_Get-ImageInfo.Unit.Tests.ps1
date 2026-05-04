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
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock Write-InfoLog {}
        Mock Write-ErrorLog {}
        Mock -ModuleName IPAP.ImageProcessor Get-NaturalSortKey { return $PSItem }
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '源目录存在时应有返回值' {
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor {
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor {
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor {
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

    Context '目录不存在测试 - Directory Not Exists' {
        It '源目录不存在时应返回空结构' {
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $false }

            $result = Get-ImageInfo -SourceDir 'C:\non_existent'

            $result.Images | Should -BeEmpty
            $result.Count | Should -Be 0
            $result.TotalSize | Should -Be 0
        }
    }

    Context '图片格式过滤测试 - Image Format Filtering' {
        It '应只包含支持的图片格式' {
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor {
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

        It '应正确过滤不支持的格式' {
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor {
                return @(
                    [PSCustomObject]@{ Name = 'doc.pdf'; Extension = '.pdf'; Length = 1024 },
                    [PSCustomObject]@{ Name = 'file.zip'; Extension = '.zip'; Length = 2048 }
                )
            }

            $result = Get-ImageInfo -SourceDir 'C:\images'

            $result.Images | Should -BeEmpty
            $result.Count | Should -Be 0
        }

        It '应支持 WebP 格式' {
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor {
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor {
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
            Mock Test-Path -ModuleName IPAP.ImageProcessor { return $true }
            Mock Get-ChildItem -ModuleName IPAP.ImageProcessor { return @() }

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
