#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Get-PendingImage 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 五个级别覆盖续跑筛选：
    L1 全部待处理 / 全部已完成、L2 目录不存在、L3 0 字节产物与大小写、
    L4 混合场景、L5 返回元素与类型。

    该函数只做文件系统判断，因此用 TestDrive 里的真实空文件做夹具，
    不 Mock Test-Path / Get-Item。
#>

Describe 'Get-PendingImage Unit Tests' -Tag 'Get-PendingImage', 'IPAP' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        function New-FakeImage {
            param([string]$Name)
            [PSCustomObject]@{ Name = $Name; FullName = "C:\src\$Name" }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $Script:OutDir = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'out') -Force |
            Select-Object -ExpandProperty FullName
        $Script:Images = @(
            New-FakeImage -Name '1.jpg'
            New-FakeImage -Name '2.jpg'
            New-FakeImage -Name '3.jpg'
        )
    }

    Context 'L1 正常筛选' {
        It '产物全都不存在时应返回全部图片' {
            $Result = @(InModuleScope IPAP -Parameters @{ Items = $Script:Images; Dir = $Script:OutDir } -ScriptBlock {
                    param($Items, $Dir)
                    Get-PendingImage -Images $Items -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 3
        }

        It '产物全都存在时应返回空' {
            foreach ($name in @('1.webp', '2.webp', '3.webp')) {
                [IO.File]::WriteAllBytes((Join-Path $Script:OutDir $name), [byte[]]::new(1))
            }

            $Result = @(InModuleScope IPAP -Parameters @{ Items = $Script:Images; Dir = $Script:OutDir } -ScriptBlock {
                    param($Items, $Dir)
                    Get-PendingImage -Images $Items -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 0
        }
    }

    Context 'L2 异常与边界' {
        It '输出目录不存在时应返回全部图片（不抛异常）' {
            $Missing = Join-Path $TestDrive 'no-such-dir'

            $Result = @(InModuleScope IPAP -Parameters @{ Items = $Script:Images; Dir = $Missing } -ScriptBlock {
                    param($Items, $Dir)
                    Get-PendingImage -Images $Items -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 3
        }

        It '0 字节产物应视为待处理' {
            New-Item -ItemType File -Path (Join-Path $Script:OutDir '1.webp') -Force | Out-Null

            $Result = @(InModuleScope IPAP -Parameters @{ Items = @($Script:Images[0]); Dir = $Script:OutDir } -ScriptBlock {
                    param($Items, $Dir)
                    Get-PendingImage -Images $Items -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 1
            $Result[0].Name | Should -Be '1.jpg'
        }

        It '空图片集合应返回空' {
            $Result = @(InModuleScope IPAP -Parameters @{ Dir = $Script:OutDir } -ScriptBlock {
                    param($Dir)
                    Get-PendingImage -Images @() -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 0
        }
    }

    Context 'L3 格式与命名' {
        It '应按 OutputFormat 匹配扩展名（jpg 产物不满足 webp）' {
            New-Item -ItemType File -Path (Join-Path $Script:OutDir '1.jpg') -Force | Out-Null

            $Result = @(InModuleScope IPAP -Parameters @{ Items = @($Script:Images[0]); Dir = $Script:OutDir } -ScriptBlock {
                    param($Items, $Dir)
                    Get-PendingImage -Images $Items -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 1
        }

        It 'OutputFormat 为 jpg 时应匹配 jpg 产物' {
            [IO.File]::WriteAllBytes((Join-Path $Script:OutDir '1.jpg'), [byte[]]::new(1))

            $Result = @(InModuleScope IPAP -Parameters @{ Items = @($Script:Images[0]); Dir = $Script:OutDir } -ScriptBlock {
                    param($Items, $Dir)
                    Get-PendingImage -Images $Items -OutputDir $Dir -OutputFormat 'jpg'
                })

            $Result.Count | Should -Be 0
        }

        It 'OutputFormat 为非法值时应被 ValidateSet 拒绝' {
            { InModuleScope IPAP -Parameters @{ Items = $Script:Images; Dir = $Script:OutDir } -ScriptBlock {
                    param($Items, $Dir)
                    Get-PendingImage -Images $Items -OutputDir $Dir -OutputFormat 'bmp'
                } } | Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])
        }
    }

    Context 'L4 混合场景' {
        It '只返回缺少产物的那一张' {
            [IO.File]::WriteAllBytes((Join-Path $Script:OutDir '1.webp'), [byte[]]::new(1))
            [IO.File]::WriteAllBytes((Join-Path $Script:OutDir '3.webp'), [byte[]]::new(1))

            $Result = @(InModuleScope IPAP -Parameters @{ Items = $Script:Images; Dir = $Script:OutDir } -ScriptBlock {
                    param($Items, $Dir)
                    Get-PendingImage -Images $Items -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 1
            $Result[0].Name | Should -Be '2.jpg'
        }

        It '只有 FullName 没有 Name 的对象也应被正确处理' {
            $OddImage = [PSCustomObject]@{ FullName = 'C:\src\9.jpg' }

            $Result = @(InModuleScope IPAP -Parameters @{ Item = $OddImage; Dir = $Script:OutDir } -ScriptBlock {
                    param($Item, $Dir)
                    Get-PendingImage -Images @($Item) -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 1
        }
    }

    Context 'L5 输出契约' {
        It '应原样返回传入的图片对象' {
            $Result = @(InModuleScope IPAP -Parameters @{ Item = $Script:Images[0]; Dir = $Script:OutDir } -ScriptBlock {
                    param($Item, $Dir)
                    Get-PendingImage -Images @($Item) -OutputDir $Dir -OutputFormat 'webp'
                })

            $Result.Count | Should -Be 1
            $Result[0].Name | Should -Be '1.jpg'
            $Result[0].FullName | Should -Be 'C:\src\1.jpg'
        }
    }
}
