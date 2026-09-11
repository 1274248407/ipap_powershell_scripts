#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - PathConfiguration 单元测试
.DESCRIPTION
    测试 PathConfiguration 类的构造函数、属性初始化、路径拼接逻辑和异常处理。
    覆盖正常路径、可选参数组合和各类输入验证边界情况。
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

    Context '构造函数 - 正常执行路径' {
        It '应正确设置 ProjectRoot 属性' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.ProjectRoot | Should -Be $p
            }
        }

        It '应自动拼接 BinPath 为 ProjectRoot/bin' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.BinPath | Should -Be (Join-Path $p 'bin')
            }
        }

        It '应自动拼接 ConfigPath 为 ProjectRoot/config.toml' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.ConfigPath | Should -Be (Join-Path $p 'config.toml')
            }
        }

        It '不传 BaseProjectDir 时应为 null' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.BaseProjectDir | Should -BeNullOrEmpty
            }
        }

        It '不传 SourceDir 时应为 null' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, $null)
                $config.SourceDir | Should -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - 可选参数' {
        It '传入 BaseProjectDir 时应正确设置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, 'BaseDirValue', $null)
                $config.BaseProjectDir | Should -Be 'BaseDirValue'
            }
        }

        It '传入 SourceDir 时应正确设置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, 'SourceDirValue')
                $config.SourceDir | Should -Be 'SourceDirValue'
            }
        }

        It '同时传入 BaseProjectDir 和 SourceDir 时应正确设置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, 'BaseDirValue', 'SourceDirValue')
                $config.BaseProjectDir | Should -Be 'BaseDirValue'
                $config.SourceDir | Should -Be 'SourceDirValue'
            }
        }

        It '传入空字符串作为 BaseProjectDir 时应接受' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, '', $null)
                $config.BaseProjectDir | Should -Be ''
            }
        }

        It '传入空字符串作为 SourceDir 时应接受' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, '')
                $config.SourceDir | Should -Be ''
            }
        }
    }

    Context '构造函数 - 异常路径' {
        It 'ProjectRoot 为空字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [PathConfiguration]::new('', $null, $null) } | Should -Throw -ExpectedMessage '*ProjectRoot 不能为空*'
            }
        }

        It 'ProjectRoot 为 null 时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [PathConfiguration]::new($null, $null, $null) } | Should -Throw -ExpectedMessage '*ProjectRoot 不能为空*'
            }
        }

        It 'ProjectRoot 为空白字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [PathConfiguration]::new('   ', $null, $null) } | Should -Throw -ExpectedMessage '*ProjectRoot 不能为空*'
            }
        }

        It 'ProjectRoot 指向不存在的目录时应抛出 DirectoryNotFoundException' {
            InModuleScope IPAP {
                $nonExistent = Join-Path $TestDrive 'DoesNotExist_ABC123'
                { [PathConfiguration]::new($nonExistent, $null, $null) } | Should -Throw -ExpectedMessage '*目录不存在*'
            }
        }

        It 'ProjectRoot 的异常消息应包含路径值' {
            InModuleScope IPAP {
                $nonExistent = Join-Path $TestDrive 'NoSuchDir_XYZ'
                { [PathConfiguration]::new($nonExistent, $null, $null) } | Should -Throw "*$nonExistent*"
            }
        }
    }

    Context '构造函数 - 可选参数验证' {
        It '应返回 PathConfiguration 实例' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, $null)
                $config | Should -BeOfType 'PathConfiguration'
            }
        }

        It '应支持可选参数透传' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config = [PathConfiguration]::new($p, $null, 'SourceDirValue')
                $config.SourceDir | Should -Be 'SourceDirValue'
            }
        }

        It 'ProjectRoot 无效时应抛出异常' {
            InModuleScope IPAP {
                { [PathConfiguration]::new('', $null, $null) } | Should -Throw
            }
        }
    }

    Context '属性类型验证' {
        It '所有属性应为 string 类型' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
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
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $config1 = [PathConfiguration]::new($p, 'Base1', $null)
                $config2 = [PathConfiguration]::new($p, 'Base2', $null)
                $config1.BaseProjectDir | Should -Be 'Base1'
                $config2.BaseProjectDir | Should -Be 'Base2'
            }
        }
    }
}
