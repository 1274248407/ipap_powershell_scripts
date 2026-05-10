#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Workflow - Test-UpscaleResult 单元测试
.DESCRIPTION
    测试 Test-UpscaleResult 函数的结果验证逻辑，包括边界条件和错误处理。
#>

Describe 'Test-UpscaleResult Unit Tests' -Tag 'Test-UpscaleResult', 'IPAP.Workflow' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psd1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.Workflow Write-InfoLog {}
        Mock -ModuleName IPAP.Workflow Write-WarningLog {}
        Mock -ModuleName IPAP.Workflow Write-ErrorLog {}
        Mock -ModuleName IPAP.Workflow Get-ChildItem { return @() }
    }

    AfterAll {
        Remove-Module 'IPAP.Workflow' -ErrorAction SilentlyContinue
    }

    Context '正常处理结果 - Normal Processing Results' {
        It '所有图片处理成功时应返回 $true' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' },
                    [PSCustomObject]@{ Name = 'image2.jpg'; Extension = '.jpg' },
                    [PSCustomObject]@{ Name = 'image3.png'; Extension = '.png' }
                )
            }

            $result = Test-UpscaleResult -ExpectedCount 3 -OutputDir 'C:\output'

            $result | Should -Be $true
        }

        It '部分成功时应返回 $false' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' },
                    [PSCustomObject]@{ Name = 'image2.jpg'; Extension = '.jpg' }
                )
            }

            $result = Test-UpscaleResult -ExpectedCount 5 -OutputDir 'C:\output'

            $result | Should -Be $false
        }

        It '全部失败时应返回 $false' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem { return @() }

            $result = Test-UpscaleResult -ExpectedCount 3 -OutputDir 'C:\output'

            $result | Should -Be $false
        }
    }

    Context '边界条件测试 - Boundary Conditions' {
        It 'ExpectedCount 为 0 时应返回 $false' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                )
            }

            $result = Test-UpscaleResult -ExpectedCount 0 -OutputDir 'C:\output'

            $result | Should -Be $false
        }

        It 'ExpectedCount 为负数时应处理' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem { return @() }

            $result = Test-UpscaleResult -ExpectedCount -1 -OutputDir 'C:\output'

            $result | Should -Be $false
        }

        It 'OutputDir 为空字符串时应处理' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem { throw 'Path cannot be empty' }

            { Test-UpscaleResult -ExpectedCount 3 -OutputDir '' } | Should -Throw
        }

        It 'OutputDir 为 $null 时应处理' {
            { Test-UpscaleResult -ExpectedCount 3 -OutputDir $null } | Should -Throw
        }
    }

    Context 'ProcessResult 参数测试 - ProcessResult Parameter' {
        It '提供 ProcessResult 时应记录对比信息' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                )
            }

            $processResult = @{ SuccessCount = 1; FailedCount = 0 }
            $result = Test-UpscaleResult -ExpectedCount 1 -OutputDir 'C:\output' -ProcessResult $processResult

            $result | Should -Be $true
            Assert-MockCalled -ModuleName IPAP.Workflow Write-InfoLog -Exactly 2
        }

        It 'ProcessResult 与实际文件数不一致时应记录警告' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                )
            }

            $processResult = @{ SuccessCount = 3; FailedCount = 0 }
            $result = Test-UpscaleResult -ExpectedCount 3 -OutputDir 'C:\output' -ProcessResult $processResult

            $result | Should -Be $false
            Assert-MockCalled -ModuleName IPAP.Workflow Write-WarningLog -Exactly 1
        }

        It 'ProcessResult 为 $null 时不应报错' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' }
                )
            }

            $result = Test-UpscaleResult -ExpectedCount 1 -OutputDir 'C:\output' -ProcessResult $null

            $result | Should -Be $true
        }
    }

    Context '文件类型过滤测试 - File Type Filtering' {
        It '应只统计支持的图片格式' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem {
                return @(
                    [PSCustomObject]@{ Name = 'image1.jpg'; Extension = '.jpg' },
                    [PSCustomObject]@{ Name = 'image2.txt'; Extension = '.txt' },
                    [PSCustomObject]@{ Name = 'image3.png'; Extension = '.png' },
                    [PSCustomObject]@{ Name = 'image4.pdf'; Extension = '.pdf' }
                )
            }

            $result = Test-UpscaleResult -ExpectedCount 2 -OutputDir 'C:\output'

            $result | Should -Be $true
        }
    }

    Context '目录不存在测试 - Directory Not Found' {
        It 'OutputDir 不存在时应抛出异常' {
            Mock -ModuleName IPAP.Workflow Get-ChildItem { throw 'Path not found' }

            { Test-UpscaleResult -ExpectedCount 3 -OutputDir 'C:\nonexistent' } | Should -Throw
        }
    }
}