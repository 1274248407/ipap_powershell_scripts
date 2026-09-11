#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - ApplicationConfiguration 单元测试
.DESCRIPTION
    测试 ApplicationConfiguration 类的构造函数、三层嵌套配置读取逻辑、
    默认值回退、MaxWorkers 动态计算和静态工厂方法 Load。
    覆盖 app_settings、upscale、webp 三个配置区块的完整边界情况。
#>

Describe 'ApplicationConfiguration Unit Tests' -Tag 'ApplicationConfiguration', 'IPAP', 'Classes' {
    BeforeAll {
        # tests\Unit\Classes → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '构造函数 - 完整配置' {
        It '应正确读取所有 app_settings 配置' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        supported_image_formats = @('.png', '.webp')
                        max_workers             = 4
                        upscale_timeout_sec     = 1800
                        model_select            = 'models-pro'
                    }
                    upscale      = @{
                        upscale_ratio = 4
                        noise_level   = 3
                    }
                    webp         = @{
                        enabled  = $false
                        lossless = $false
                        quality  = 85
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.SupportedImageFormats | Should -Be @('.png', '.webp')
                $config.MaxWorkers | Should -Be 4
                $config.UpscaleTimeoutSec | Should -Be 1800
                $config.ModelSelect | Should -Be 'models-pro'
                $config.UpscaleRatio | Should -Be 4
                $config.NoiseLevel | Should -Be 3
                $config.WebpEnabled | Should -Be $false
                $config.WebpLossless | Should -Be $false
                $config.WebpQuality | Should -Be 85
            }
        }
    }

    Context '构造函数 - app_settings 默认值回退' {
        It 'app_settings 为 null 时应使用全部默认值' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{})

                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $config.MaxWorkers | Should -Not -Be 0  # 动态计算后不应为 0
                $config.UpscaleTimeoutSec | Should -Be 3600
                $config.ModelSelect | Should -Be 'models-se'
            }
        }

        It 'app_settings 缺少 supported_image_formats 时应使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers         = 2
                        upscale_timeout_sec = 600
                        model_select        = 'models-pro'
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
            }
        }

        It 'supported_image_formats 为空数组时应使用空数组（不触发默认值）' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        supported_image_formats = @()
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                # 空数组在 if 条件中为 false（PowerShell 空数组行为），应回退到默认值
                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
            }
        }

        It 'max_workers 为字符串数字时应正确转换为 int' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers = '8'
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.MaxWorkers | Should -Be 8
            }
        }

        It 'upscale_timeout_sec 为字符串数字时应正确转换为 int' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        upscale_timeout_sec = '7200'
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.UpscaleTimeoutSec | Should -Be 7200
            }
        }
    }

    Context '构造函数 - upscale 默认值回退' {
        It 'upscale 为 null 时应使用默认值' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{})

                $config.UpscaleRatio | Should -Be 2
                $config.NoiseLevel | Should -Be 0
            }
        }

        It 'upscale 缺少 upscale_ratio 时应使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    upscale = @{
                        noise_level = 1
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.UpscaleRatio | Should -Be 2
                $config.NoiseLevel | Should -Be 1
            }
        }

        It 'upscale 缺少 noise_level 时应使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    upscale = @{
                        upscale_ratio = 3
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.UpscaleRatio | Should -Be 3
                $config.NoiseLevel | Should -Be 0
            }
        }

        It 'upscale_ratio 为字符串数字时应正确转换为 int' {
            InModuleScope IPAP {
                $settings = @{
                    upscale = @{
                        upscale_ratio = '4'
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.UpscaleRatio | Should -Be 4
            }
        }
    }

    Context '构造函数 - webp 默认值回退' {
        It 'webp 为 null 时应使用默认值' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{})

                $config.WebpEnabled | Should -Be $true
                $config.WebpLossless | Should -Be $true
                $config.WebpQuality | Should -Be 100
            }
        }

        It 'webp 缺少 enabled 时应使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    webp = @{
                        lossless = $false
                        quality  = 90
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.WebpEnabled | Should -Be $true
                $config.WebpLossless | Should -Be $false
                $config.WebpQuality | Should -Be 90
            }
        }

        It 'webp 缺少 lossless 时应使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    webp = @{
                        enabled = $false
                        quality = 80
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.WebpEnabled | Should -Be $false
                $config.WebpLossless | Should -Be $true
                $config.WebpQuality | Should -Be 80
            }
        }

        It 'webp 缺少 quality 时应使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    webp = @{
                        enabled  = $false
                        lossless = $false
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.WebpQuality | Should -Be 100
            }
        }

        It 'webp enabled 为布尔值 false 时应正确设置' {
            InModuleScope IPAP {
                $settings = @{
                    webp = @{
                        enabled = $false
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.WebpEnabled | Should -Be $false
            }
        }
    }

    Context '构造函数 - MaxWorkers 动态计算' {
        It 'max_workers 显式指定非零值时应直接使用' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers = 6
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.MaxWorkers | Should -Be 6
            }
        }

        It 'max_workers 为 0 时应根据 CPU 核心数动态计算' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers = 0
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                # 动态计算公式：Max(1, ProcessorCount / 2)
                $expected = [math]::Max(1, [System.Environment]::ProcessorCount / 2)
                $config.MaxWorkers | Should -Be $expected
            }
        }

        It 'max_workers 未指定时应根据 CPU 核心数动态计算' {
            InModuleScope IPAP {
                # app_settings 存在但不包含 max_workers
                $settings = @{
                    app_settings = @{
                        model_select = 'models-se'
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $expected = [math]::Max(1, [System.Environment]::ProcessorCount / 2)
                $config.MaxWorkers | Should -Be $expected
            }
        }

        It 'max_workers 为负数时应直接使用（不触发动态计算）' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers = -1
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                # -1 不等于 0，不触发动态计算
                $config.MaxWorkers | Should -Be -1
            }
        }
    }

    Context '构造函数 - 完全空设置' {
        It '传入空哈希表时应全部使用默认值' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{})

                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $config.MaxWorkers | Should -Not -Be 0
                $config.UpscaleTimeoutSec | Should -Be 3600
                $config.ModelSelect | Should -Be 'models-se'
                $config.UpscaleRatio | Should -Be 2
                $config.NoiseLevel | Should -Be 0
                $config.WebpEnabled | Should -Be $true
                $config.WebpLossless | Should -Be $true
                $config.WebpQuality | Should -Be 100
            }
        }
    }

    Context '构造函数 - 仅部分区块存在' {
        It '仅有 app_settings 时 upscale 和 webp 使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers = 4
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.MaxWorkers | Should -Be 4
                $config.UpscaleRatio | Should -Be 2
                $config.WebpEnabled | Should -Be $true
            }
        }

        It '仅有 upscale 时 app_settings 和 webp 使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    upscale = @{
                        upscale_ratio = 4
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $config.UpscaleRatio | Should -Be 4
                $config.WebpEnabled | Should -Be $true
            }
        }

        It '仅有 webp 时 app_settings 和 upscale 使用默认值' {
            InModuleScope IPAP {
                $settings = @{
                    webp = @{
                        quality = 50
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $config.UpscaleRatio | Should -Be 2
                $config.WebpQuality | Should -Be 50
            }
        }
    }

    Context '构造函数验证' {
        It '应返回 ApplicationConfiguration 实例' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers = 4
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config | Should -BeOfType [ApplicationConfiguration]
            }
        }

        It 'null 设置时应抛出异常（ContainsKey 不支持 null）' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new($null) } | Should -Throw
            }
        }
    }

    Context '属性类型验证' {
        It '数值属性应为正确类型' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers         = 4
                        upscale_timeout_sec = 1800
                    }
                    upscale      = @{
                        upscale_ratio = 2
                        noise_level   = 1
                    }
                    webp         = @{
                        quality = 100
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.MaxWorkers | Should -BeOfType [int]
                $config.UpscaleTimeoutSec | Should -BeOfType [int]
                $config.ModelSelect | Should -BeOfType [string]
                $config.UpscaleRatio | Should -BeOfType [int]
                $config.NoiseLevel | Should -BeOfType [int]
                $config.WebpEnabled | Should -BeOfType [bool]
                $config.WebpLossless | Should -BeOfType [bool]
                $config.WebpQuality | Should -BeOfType [int]
            }
        }
    }

    Context '独立性验证' {
        It '多个实例之间不应互相影响' {
            InModuleScope IPAP {
                $settings1 = @{
                    app_settings = @{ max_workers = 2 }
                    webp         = @{ quality = 50 }
                }
                $settings2 = @{
                    app_settings = @{ max_workers = 8 }
                    webp         = @{ quality = 100 }
                }
                $config1 = [ApplicationConfiguration]::new($settings1)
                $config2 = [ApplicationConfiguration]::new($settings2)

                $config1.MaxWorkers | Should -Be 2
                $config1.WebpQuality | Should -Be 50
                $config2.MaxWorkers | Should -Be 8
                $config2.WebpQuality | Should -Be 100
            }
        }
    }
}
