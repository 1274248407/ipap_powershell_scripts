#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - IPAPConfiguration 单元测试
.DESCRIPTION
    测试 IPAPConfiguration 聚合类的构造函数、静态 Load 方法、
    ReadConfigFile（TOML 读取与 Windows 路径转义修复）和 MergeSettings（浅合并逻辑）。
    使用真实目录和文件替代全局 Mock Test-Path，避免干扰
    PathConfiguration 构造函数中的目录验证。
#>

Describe 'IPAPConfiguration Unit Tests' -Tag 'IPAPConfiguration', 'IPAP', 'Classes' {
    BeforeAll {
        # tests\Unit\Classes → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '构造函数 - 正常路径' {
        It '应正确聚合四个子配置对象' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $toolConfig = [ToolConfiguration]::new($pathConfig, @{ paths = @{} })
                $appConfig = [ApplicationConfiguration]::new(@{})
                $projectConfig = [ProjectConfiguration]::new(@{})

                $config = [IPAPConfiguration]::new($pathConfig, $toolConfig, $appConfig, $projectConfig)

                $config.Paths | Should -Be $pathConfig
                $config.Tools | Should -Be $toolConfig
                $config.App | Should -Be $appConfig
                $config.Project | Should -Be $projectConfig
            }
        }

        It '每个子配置应为正确的类型' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $toolConfig = [ToolConfiguration]::new($pathConfig, @{ paths = @{} })
                $appConfig = [ApplicationConfiguration]::new(@{})
                $projectConfig = [ProjectConfiguration]::new(@{})

                $config = [IPAPConfiguration]::new($pathConfig, $toolConfig, $appConfig, $projectConfig)

                $config.Paths | Should -BeOfType 'PathConfiguration'
                $config.Tools | Should -BeOfType 'ToolConfiguration'
                $config.App | Should -BeOfType 'ApplicationConfiguration'
                $config.Project | Should -BeOfType 'ProjectConfiguration'
            }
        }
    }

    Context '静态方法 Load - 配置文件不存在' {
        It 'config.toml 不存在时应使用默认配置创建实例' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }

                $config = [IPAPConfiguration]::Load($p)

                $config | Should -BeOfType 'IPAPConfiguration'
                $config.Paths.ProjectRoot | Should -Be $p
            }
        }

        It 'config.toml 不存在时应记录 Info 日志' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }

                [IPAPConfiguration]::Load($p) | Out-Null

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter {
                    $Level -eq 'Info' -and $Message -like '*配置文件不存在*'
                }
            }
        }

        It 'config.toml 不存在时应使用默认 app_settings' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $config.App.ModelSelect | Should -Be 'models-se'
                $config.App.UpscaleRatio | Should -Be 2
                $config.App.WebpEnabled | Should -Be $true
            }
        }

        It 'config.toml 不存在时 Project 配置应为默认值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }

                $config = [IPAPConfiguration]::Load($p)

                $config.Project.Author | Should -Be ''
                $config.Project.OriginalTitle | Should -Be ''
            }
        }
    }

    Context '静态方法 Load - PSToml 模块未找到' {
        It 'PSToml 不可用时应使用默认配置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.ModelSelect | Should -Be 'models-se'
            }
        }

        It 'PSToml 不可用时应记录 Info 日志' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }

                [IPAPConfiguration]::Load($p) | Out-Null

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter {
                    $Level -eq 'Info' -and $Message -like '*PSToml 模块未找到*'
                }
            }
        }
    }

    Context '静态方法 Load - TOML 解析成功' {
        It '应正确解析并合并用户配置' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    return @{ app_settings = @{ model_select = 'models-pro' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.ModelSelect | Should -Be 'models-pro'
                $config.App.UpscaleTimeoutSec | Should -Be 3600
            }
        }

        It '路径配置中的 base_project_dir 和 source_dir 应正确透传' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    return @{ paths = @{ base_project_dir = 'custom_base'; source_dir = 'custom_source' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.Paths.BaseProjectDir | Should -Be 'custom_base'
                $config.Paths.SourceDir | Should -Be 'custom_source'
            }
        }
    }

    Context '静态方法 Load - TOML 解析失败' {
        It '解析失败且非转义问题时应抛出异常' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    throw [System.Exception]::new('Unexpected token')
                }

                { [IPAPConfiguration]::Load($p) } | Should -Throw '*无法解析 config.toml*'
            }
        }
    }

    Context '静态方法 Load - Windows 路径转义自动修复' {
        It '检测到反斜杠转义问题时应尝试自动修复' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }

                $script:tomlCallCount = 0
                Mock -CommandName ConvertFrom-Toml {
                    $script:tomlCallCount++
                    if ($script:tomlCallCount -eq 1)
                    {
                        throw [System.Exception]::new('Unexpected escape character in string')
                    }
                    return @{ paths = @{ source_dir = 'C:\Users\test\images' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.Paths.SourceDir | Should -Be 'C:\Users\test\images'
            }
        }

        It '转义修复成功后应记录 Warning 日志' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }

                $script:tomlCallCount = 0
                Mock -CommandName ConvertFrom-Toml {
                    $script:tomlCallCount++
                    if ($script:tomlCallCount -eq 1)
                    {
                        throw [System.Exception]::new('Unexpected escape character')
                    }
                    return @{ paths = @{ source_dir = 'C:\test' } }
                }

                [IPAPConfiguration]::Load($p) | Out-Null

                Should -Invoke -CommandName Write-LogEntry -ParameterFilter {
                    $Level -eq 'Warning' -and $Message -like '*自动修复成功*'
                }
            }
        }
    }

    Context 'MergeSettings 方法 - 浅合并逻辑' {
        It '用户配置覆盖默认值时应使用用户值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    return @{ app_settings = @{ model_select = 'custom-model' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.ModelSelect | Should -Be 'custom-model'
                $config.App.UpscaleTimeoutSec | Should -Be 3600
            }
        }

        It '用户配置中存在默认配置没有的键时应直接添加' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    return @{ custom_section = @{ custom_key = 'custom_value' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.ModelSelect | Should -Be 'models-se'
            }
        }

        It '用户配置覆盖嵌套哈希表的子键时应只影响被覆盖的子键' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    return @{ webp = @{ quality = 75 } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.App.WebpQuality | Should -Be 75
                $config.App.WebpEnabled | Should -Be $true
                $config.App.WebpLossless | Should -Be $true
            }
        }
    }

    Context 'ReadConfigFile - 读取流程' {
        It 'config.toml 存在时应尝试读取文件内容' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml { return @{} }

                [IPAPConfiguration]::Load($p) | Out-Null

                Should -Invoke -CommandName Get-Content
            }
        }
    }

    Context 'ReadConfigFile - OrderedDictionary 转换' {
        It 'OrderedDictionary 类型的子配置应被转换为 hashtable' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    return @{ paths = [ordered]@{ base_project_dir = ''; source_dir = '' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.Paths | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context '边界情况 - 多种配置组合' {
        It '所有配置区块都存在时应正确合并' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    return @{
                        paths        = @{ source_dir = 'custom_source' }
                        project      = @{ author = '鲁迅'; original_title = '呐喊' }
                        app_settings = @{ model_select = 'models-pro'; max_workers = 4 }
                        upscale      = @{ upscale_ratio = 4 }
                        webp         = @{ quality = 80 }
                    }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.Paths.SourceDir | Should -Be 'custom_source'
                $config.Project.Author | Should -Be '鲁迅'
                $config.Project.OriginalTitle | Should -Be '呐喊'
                $config.App.ModelSelect | Should -Be 'models-pro'
                $config.App.MaxWorkers | Should -Be 4
                $config.App.UpscaleRatio | Should -Be 4
                $config.App.WebpQuality | Should -Be 80
            }
        }

        It '仅有 project 配置时其他子配置应为默认值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $configToml = Join-Path $p 'config.toml'
                New-Item -Path $configToml -ItemType File -Force | Out-Null

                Mock -CommandName Write-LogEntry { }
                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ConvertFrom-Toml' } {
                    return [PSCustomObject]@{ Name = 'ConvertFrom-Toml' }
                }
                Mock -CommandName Get-Content { return '' }
                Mock -CommandName Import-Module { }
                Mock -CommandName ConvertFrom-Toml {
                    return @{ project = @{ author = '鲁迅' } }
                }

                $config = [IPAPConfiguration]::Load($p)

                $config.Project.Author | Should -Be '鲁迅'
                $config.App.ModelSelect | Should -Be 'models-se'
                $config.App.UpscaleRatio | Should -Be 2
            }
        }
    }

    Context '构造函数 - 独立性验证' {
        It '修改一个实例不应影响另一个实例' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $toolConfig = [ToolConfiguration]::new($pathConfig, @{ paths = @{} })

                $appConfig1 = [ApplicationConfiguration]::new(@{ webp = @{ quality = 50 } })
                $projectConfig1 = [ProjectConfiguration]::new(@{ project = @{ author = '作者A' } })

                $appConfig2 = [ApplicationConfiguration]::new(@{ webp = @{ quality = 90 } })
                $projectConfig2 = [ProjectConfiguration]::new(@{ project = @{ author = '作者B' } })

                $config1 = [IPAPConfiguration]::new($pathConfig, $toolConfig, $appConfig1, $projectConfig1)
                $config2 = [IPAPConfiguration]::new($pathConfig, $toolConfig, $appConfig2, $projectConfig2)

                $config1.App.WebpQuality | Should -Be 50
                $config1.Project.Author | Should -Be '作者A'
                $config2.App.WebpQuality | Should -Be 90
                $config2.Project.Author | Should -Be '作者B'
            }
        }
    }
}
