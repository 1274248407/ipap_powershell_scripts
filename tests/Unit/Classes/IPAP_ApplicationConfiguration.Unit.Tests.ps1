#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - ApplicationConfiguration 单元测试
.DESCRIPTION
    测试 ApplicationConfiguration 类的构造函数、三层嵌套配置读取逻辑、
    默认值回退、MaxWorkers 动态计算和静态工厂方法 Load。
    覆盖 app_settings、upscale、webp 三个配置区块的完整边界情况。
    按 doc/单元测试方法论.md 的 L1-L5 覆盖：
    - L1 正常流程：完整配置读取、MaxWorkers 动态计算、构造函数可用性
    - L2 异常流程：非法输入抛 ArgumentException
    - L3 边界数据：区块缺失 / 空设置 / 默认值回退 / 越界钳制 / 字符串数字与布尔转换
    - L4 分支覆盖：数据缺失与越界的回退分支随 L3 用例覆盖，不单列
    - L5 输出字段：属性类型、实例独立性
    本文件是纯类测试：不 Mock、不做文件 IO、不共享跨用例状态，因此不设 BeforeEach 共享夹具，
    §7.7 的清理要求也因不产生测试数据而天然满足。
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

    Context '构造函数 - 完整配置（L1）' {
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

    Context '构造函数 - app_settings 默认值回退（L3）' {
        It 'app_settings 为 null 时应使用 app_settings 默认值' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{})

                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $config.MaxWorkers | Should -Be ([math]::Max(1, [System.Environment]::ProcessorCount / 2))
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

        It 'supported_image_formats 为空数组时应保留空数组（用户明确声明不支持任何格式）' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        supported_image_formats = @()
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                # ?? 只检查 null，空数组非 null，应保留用户设置
                $config.SupportedImageFormats | Should -Be @()
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

        It 'upscale_timeout_sec 为 0 或负数时应回退到默认值' {
            InModuleScope IPAP {
                $configZero = [ApplicationConfiguration]::new(@{ app_settings = @{ upscale_timeout_sec = 0 } })
                $configNeg = [ApplicationConfiguration]::new(@{ app_settings = @{ upscale_timeout_sec = -100 } })

                # 无效超时值应回退到默认 3600 秒
                $configZero.UpscaleTimeoutSec | Should -Be 3600
                $configNeg.UpscaleTimeoutSec | Should -Be 3600
            }
        }

        It 'upscale_timeout_sec 为 1 时应保持不变（刚好不触发 -lt 1）' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{ app_settings = @{ upscale_timeout_sec = 1 } })

                $config.UpscaleTimeoutSec | Should -Be 1
            }
        }

        It 'supported_image_formats 为 $null（显式）时应回退到默认值' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        supported_image_formats = $null
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
            }
        }

        It 'model_select 为非字符串值时应转换为字符串' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        model_select = 123
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.ModelSelect | Should -BeExactly '123'
            }
        }
    }

    Context '构造函数 - upscale 默认值回退（L3）' {
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

        It 'noise_level 为字符串数字时应正确转换为 int' {
            InModuleScope IPAP {
                $settings = @{
                    upscale = @{
                        noise_level = '2'
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.NoiseLevel | Should -Be 2
            }
        }

        It 'upscale_ratio 超出有效值域时应钳制到边界' {
            InModuleScope IPAP {
                # Real-CUGAN -s scale 有效值: 1/2/3/4
                $configLow = [ApplicationConfiguration]::new(@{ upscale = @{ upscale_ratio = 0 } })
                $configHigh = [ApplicationConfiguration]::new(@{ upscale = @{ upscale_ratio = 10 } })
                $configNeg = [ApplicationConfiguration]::new(@{ upscale = @{ upscale_ratio = -2 } })

                $configLow.UpscaleRatio | Should -Be 1
                $configHigh.UpscaleRatio | Should -Be 4
                $configNeg.UpscaleRatio | Should -Be 1
            }
        }

        It 'noise_level 超出有效值域时应钳制到边界' {
            InModuleScope IPAP {
                # Real-CUGAN -n noise-level 有效值: -1/0/1/2/3
                $configLow = [ApplicationConfiguration]::new(@{ upscale = @{ noise_level = -5 } })
                $configHigh = [ApplicationConfiguration]::new(@{ upscale = @{ noise_level = 10 } })

                $configLow.NoiseLevel | Should -Be -1
                $configHigh.NoiseLevel | Should -Be 3
            }
        }

        It 'upscale_ratio 为边界值 1 时应保持不变（刚好不触发 Max 下限）' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{ upscale = @{ upscale_ratio = 1 } })

                $config.UpscaleRatio | Should -Be 1
            }
        }

        It 'noise_level 为边界值 3 时应保持不变（刚好不触发 Min 上限）' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{ upscale = @{ noise_level = 3 } })

                $config.NoiseLevel | Should -Be 3
            }
        }
    }

    Context '构造函数 - webp 默认值回退（L3）' {
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

                $config.WebpEnabled | Should -Be $false
                $config.WebpLossless | Should -Be $false
                $config.WebpQuality | Should -Be 100
            }
        }

        It 'webp quality 为字符串数字时应正确转换为 int' {
            InModuleScope IPAP {
                $settings = @{
                    webp = @{
                        quality = '85'
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                $config.WebpQuality | Should -Be 85
            }
        }

        It 'webp quality 超出有效值域时应钳制到 0~100' {
            InModuleScope IPAP {
                # cwebp -q 有效范围: 0~100
                $configLow = [ApplicationConfiguration]::new(@{ webp = @{ quality = -10 } })
                $configHigh = [ApplicationConfiguration]::new(@{ webp = @{ quality = 200 } })

                $configLow.WebpQuality | Should -Be 0
                $configHigh.WebpQuality | Should -Be 100
            }
        }

        It 'webp quality 为边界值 0 时应保持不变（刚好不触发 Max 下限）' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{ webp = @{ quality = 0 } })

                $config.WebpQuality | Should -Be 0
            }
        }

        It 'webp quality 为边界值 100 时应保持不变（刚好不触发 Min 上限）' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{ webp = @{ quality = 100 } })

                $config.WebpQuality | Should -Be 100
            }
        }
    }

    Context '构造函数 - 分级阈值（L3）' {
        It '缺少 classifier 区块时应使用默认阈值 6.0 / 3.0' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{})

                $config.HighDetailThreshold | Should -Be 6.0
                $config.MediumDetailThreshold | Should -Be 3.0
            }
        }

        It 'classifier 提供数值时应按原值读取' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{
                        classifier = @{ high_detail = 10.5; medium_detail = 4.5 }
                    })

                $config.HighDetailThreshold | Should -Be 10.5
                $config.MediumDetailThreshold | Should -Be 4.5
            }
        }

        It 'classifier 提供字符串数字时应转换为 double' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{
                        classifier = @{ high_detail = '8.5'; medium_detail = '2.5' }
                    })

                $config.HighDetailThreshold | Should -Be 8.5
                $config.MediumDetailThreshold | Should -Be 2.5
            }
        }

        It 'classifier 缺失单个键时应回退对应默认值' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{ classifier = @{ high_detail = 9.0 } })

                $config.HighDetailThreshold | Should -Be 9.0
                $config.MediumDetailThreshold | Should -Be 3.0
            }
        }

        It 'classifier 非字典时应抛 ArgumentException' {
            { InModuleScope IPAP { [ApplicationConfiguration]::new(@{ classifier = 'bad' }) } } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*classifier*'
        }

        It 'high_detail 非数值时应抛 ArgumentException' {
            { InModuleScope IPAP { [ApplicationConfiguration]::new(@{ classifier = @{ high_detail = 'abc' } }) } } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*high_detail*'
        }

        It 'medium_detail 高于 high_detail 时应钳制为 high_detail' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{
                        classifier = @{ high_detail = 5.0; medium_detail = 9.0 }
                    })

                $config.MediumDetailThreshold | Should -Be 5.0
            }
        }

        It '负值应钳制为 0' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{
                        classifier = @{ high_detail = -1; medium_detail = -2 }
                    })

                $config.HighDetailThreshold | Should -Be 0
                $config.MediumDetailThreshold | Should -Be 0
            }
        }
    }

    Context '构造函数 - 布尔值转换（L3）' {
        It "webp.enabled 为字符串 'false' 时应转换为 `$false" {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{ webp = @{ enabled = 'false' } })

                $config.WebpEnabled | Should -Be $false
            }
        }

        It "webp.lossless 为字符串 'False'（大写）时应转换为 `$false" {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{ webp = @{ lossless = 'False' } })

                $config.WebpLossless | Should -Be $false
            }
        }

        It 'webp.enabled 为数字 0 或 1 时应分别转换为 $false / $true' {
            InModuleScope IPAP {
                $configZero = [ApplicationConfiguration]::new(@{ webp = @{ enabled = 0 } })
                $configOne = [ApplicationConfiguration]::new(@{ webp = @{ enabled = 1 } })

                $configZero.WebpEnabled | Should -Be $false
                $configOne.WebpEnabled | Should -Be $true
            }
        }

        It "webp.enabled 为非法字符串 'no' 时应抛出 ArgumentException" {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ webp = @{ enabled = 'no' } }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*enabled*不是有效的布尔值*'
            }
        }
    }

    Context '构造函数 - MaxWorkers 动态计算（L1/L3）' {
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

        It 'max_workers 为负数时应回退到动态计算（视为无效值）' {
            InModuleScope IPAP {
                $settings = @{
                    app_settings = @{
                        max_workers = -1
                    }
                }
                $config = [ApplicationConfiguration]::new($settings)

                # 负数与 0 同等处理，回退到 CPU 核心数动态计算
                $expected = [math]::Max(1, [System.Environment]::ProcessorCount / 2)
                $config.MaxWorkers | Should -Be $expected
            }
        }
    }

    Context '构造函数 - 完全空设置（L3）' {
        It '传入空哈希表时应全部使用默认值' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new(@{})

                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $config.MaxWorkers | Should -Be ([math]::Max(1, [System.Environment]::ProcessorCount / 2))
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

    Context '构造函数 - 仅部分区块存在（L3）' {
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

    Context '构造函数验证（L1）' {
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

        It 'null 设置时应安全处理（?? 回退到空哈希表）' {
            InModuleScope IPAP {
                $config = [ApplicationConfiguration]::new($null)

                # null 输入通过 ?? @{ } 回退，所有属性使用默认值
                $config.SupportedImageFormats | Should -Be @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
                $config.MaxWorkers | Should -Be ([math]::Max(1, [System.Environment]::ProcessorCount / 2))
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

    Context '构造函数 - 无效输入（L2）' {
        It 'max_workers 为非数字字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ app_settings = @{ max_workers = 'abc' } }) } | Should -Throw -ExpectedMessage '*max_workers*不是有效的整数*'
            }
        }

        It 'upscale_timeout_sec 为非数字字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ app_settings = @{ upscale_timeout_sec = 'not_a_number' } }) } | Should -Throw -ExpectedMessage '*upscale_timeout_sec*不是有效的整数*'
            }
        }

        It 'upscale_ratio 为非数字字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ upscale = @{ upscale_ratio = 'xyz' } }) } | Should -Throw -ExpectedMessage '*upscale_ratio*不是有效的整数*'
            }
        }

        It 'noise_level 为非数字字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ upscale = @{ noise_level = 'bad' } }) } | Should -Throw -ExpectedMessage '*noise_level*不是有效的整数*'
            }
        }

        It 'webp quality 为非数字字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ webp = @{ quality = 'abc123' } }) } | Should -Throw -ExpectedMessage '*quality*不是有效的整数*'
            }
        }

        It 'app_settings 键存在但不是字典类型时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ app_settings = 'not_a_dict' }) } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'app_settings' 必须是 IDictionary 类型，当前值类型为 'String'"
            }
        }

        It 'upscale 键存在但不是字典类型时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ upscale = 'not_a_dict' }) } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'upscale' 必须是 IDictionary 类型，当前值类型为 'String'"
            }
        }

        It 'webp 键存在但不是字典类型时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ webp = 'not_a_dict' }) } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'webp' 必须是 IDictionary 类型，当前值类型为 'String'"
            }
        }

        It "webp quality 为带小数点的字符串 '2.5' 时应抛出 ArgumentException" {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ webp = @{ quality = '2.5' } }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*quality*不是有效的整数*'
            }
        }

        It 'max_workers 为布尔值时应抛出 ArgumentException' {
            InModuleScope IPAP {
                { [ApplicationConfiguration]::new(@{ app_settings = @{ max_workers = $true } }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*max_workers*不是有效的整数*'
            }
        }
    }

    Context '属性类型验证（L5）' {
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

                $config.SupportedImageFormats | Should -BeOfType [string]
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

    Context '独立性验证（L5）' {
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
