#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - PathConfiguration 单元测试
.DESCRIPTION
    测试 PathConfiguration 的构造函数：ProjectRoot 规范化与校验、BinPath/ConfigPath 自动拼接、
    可选参数透传、属性类型与实例独立性。覆盖正常路径、可选参数组合和输入验证边界。

    夹具（§7.2 / §7.7）：共享的 MockProject 目录由 BeforeEach 创建、AfterEach 清理；
    该测试不涉及外部依赖，因此不需要任何 Mock。
#>

Describe 'PathConfiguration Unit Tests' -Tag 'PathConfiguration', 'IPAP', 'Classes' {
    BeforeAll {
        # tests\Unit\Classes → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 共享基础数据：所有用例共用的项目目录
        $script:TestRoot = Join-Path $TestDrive 'MockProject'
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        # 清理本用例产生的目录与文件（§7.7）
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        $notADirectoryFile = Join-Path $TestDrive 'NotADirectory.txt'
        if (Test-Path -LiteralPath $notADirectoryFile) {
            Remove-Item -LiteralPath $notADirectoryFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context '构造函数 - 正常执行路径' {
        It '应正确设置 ProjectRoot 属性' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.ProjectRoot | Should -Be $p
            }
        }

        It '应自动拼接 BinPath 为 ProjectRoot/bin' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.BinPath | Should -Be (Join-Path $p 'bin')
            }
        }

        It '应自动拼接 ConfigPath 为 ProjectRoot/config.toml' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.ConfigPath | Should -Be (Join-Path $p 'config.toml')
            }
        }

        It '不传 BaseProjectDir 时应为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.BaseProjectDir | Should -BeNullOrEmpty
            }
        }

        It '不传 SourceDir 时应为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.SourceDir | Should -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - 可选参数' {
        It '传入 BaseProjectDir 时应正确设置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, 'BaseDirValue', $null)
                $config.BaseProjectDir | Should -Be 'BaseDirValue'
            }
        }

        It '传入 SourceDir 时应正确设置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, 'SourceDirValue')
                $config.SourceDir | Should -Be 'SourceDirValue'
            }
        }

        It '同时传入 BaseProjectDir 和 SourceDir 时应正确设置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, 'BaseDirValue', 'SourceDirValue')
                $config.BaseProjectDir | Should -Be 'BaseDirValue'
                $config.SourceDir | Should -Be 'SourceDirValue'
            }
        }

        It '传入空字符串作为 BaseProjectDir 时应接受' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, '', $null)
                $config.BaseProjectDir | Should -Be ''
            }
        }

        It '传入空字符串作为 SourceDir 时应接受' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, '')
                $config.SourceDir | Should -Be ''
            }
        }
    }

    Context '构造函数 - 异常路径' {
        It 'ProjectRoot 为空字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [PathConfiguration]::new('', $null, $null) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*ProjectRoot 不能为空*'
            }
        }

        It 'ProjectRoot 为 null 时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [PathConfiguration]::new($null, $null, $null) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*ProjectRoot 不能为空*'
            }
        }

        It 'ProjectRoot 为空白字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [PathConfiguration]::new('   ', $null, $null) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*ProjectRoot 不能为空*'
            }
        }

        It 'ProjectRoot 指向不存在的目录时应抛出 DirectoryNotFoundException' {
            InModuleScope IPAP {
                $nonExistent = Join-Path $TestDrive 'DoesNotExist_ABC123'
                { [PathConfiguration]::new($nonExistent, $null, $null) } |
                    Should -Throw -ExceptionType ([System.IO.DirectoryNotFoundException]) -ExpectedMessage '*目录不存在*'
            }
        }

        It 'ProjectRoot 的异常消息应包含路径值' {
            InModuleScope IPAP {
                $nonExistent = Join-Path $TestDrive 'NoSuchDir_XYZ'
                { [PathConfiguration]::new($nonExistent, $null, $null) } | Should -Throw "*$nonExistent*"
            }
        }
    }

    Context '构造函数 - 输入规范化与路径类型' {
        It 'ProjectRoot 指向文件（非目录）时应抛出 DirectoryNotFoundException' {
            InModuleScope IPAP {
                # Test-Path 对文件也返回真，必须由 -PathType Container 拦住
                $file = Join-Path $TestDrive 'NotADirectory.txt'
                New-Item -Path $file -ItemType File -Force | Out-Null

                { [PathConfiguration]::new($file, $null, $null) } |
                    Should -Throw -ExceptionType ([System.IO.DirectoryNotFoundException]) -ExpectedMessage '*不是目录*'
            }
        }

        It 'ProjectRoot 带尾随空格时应存规范化后的路径' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new(($p + ' '), $null, $null)

                # Windows 把尾部空格当无意义，存下来会导致 ProjectRoot 与 BinPath 不一致
                $config.ProjectRoot | Should -Be $p
                $config.BinPath | Should -Be (Join-Path $p 'bin')
            }
        }
    }

    Context '构造函数验证' {
        It '应返回 PathConfiguration 实例' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, $null)
                $config | Should -BeOfType 'PathConfiguration'
            }
        }
    }

    Context '属性类型验证' {
        It '所有属性应为 string 类型' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.ProjectRoot | Should -BeOfType [string]
                $config.BaseProjectDir | Should -BeOfType [string]
                $config.BinPath | Should -BeOfType [string]
                $config.ConfigPath | Should -BeOfType [string]
                $config.SourceDir | Should -BeOfType [string]
            }
        }
    }

    Context '路径拼接边界' {
        It '连续创建两个实例应互不影响' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $config1 = [PathConfiguration]::new($p, 'Base1', $null)
                $config2 = [PathConfiguration]::new($p, 'Base2', $null)
                $config1.BaseProjectDir | Should -Be 'Base1'
                $config2.BaseProjectDir | Should -Be 'Base2'
            }
        }
    }
}
