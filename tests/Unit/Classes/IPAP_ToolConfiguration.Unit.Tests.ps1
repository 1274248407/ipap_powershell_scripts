#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - ToolConfiguration 单元测试
.DESCRIPTION
    测试 ToolConfiguration 类的构造函数与工具路径解析逻辑（ResolveToolPath / ResolveRealCuganPath）。
    按 docs/单元测试方法论.md 覆盖：
    L1 正常流程、L2 PathConfig/paths 类型校验、L3 缺失键与目录/空白边界、
    L4 分支（配置优先、PATH 回退、bin 递归查找）、L5 三个路径字段逐一断言。
    夹具：BeforeEach 共享 MockProject 目录并 Mock Get-Command 兜底，AfterEach 清理；
    各用例只在自己的文件树布局上做差异，故不抽共享 settings。
#>

Describe 'ToolConfiguration Unit Tests' -Tag 'ToolConfiguration', 'IPAP', 'Classes' {
    BeforeAll {
        # tests\Unit\Classes → 项目根（向上三级）
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # 共享夹具：所有用例共用的项目目录；各用例按需在其中创建 tools/ bin/ 等差异文件树
        $script:TestRoot = Join-Path $TestDrive 'MockProject'
        New-Item -Path $script:TestRoot -ItemType Directory -Force | Out-Null

        # 外部依赖：默认所有工具命令都不存在；需要命中的用例在 It 内用参数过滤覆盖
        Mock -CommandName Get-Command -ModuleName IPAP { return $null }
    }

    AfterEach {
        # 清理本用例产生的目录与文件（§7.7）
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context '构造函数 - 配置路径优先（L1）' {
        It '当配置路径存在时应使用配置路径（ffmpeg）' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $ffmpegConfigPath = Join-Path $p 'tools\ffmpeg.exe'
                New-Item -Path $ffmpegConfigPath -ItemType File -Force | Out-Null

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = 'tools\ffmpeg.exe'; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be $ffmpegConfigPath
                # 交叉校验：只配置 ffmpeg 时其余两个工具不应被污染
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }

        It '当配置路径存在时应使用配置路径（ffprobe）' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $ffprobeConfigPath = Join-Path $p 'tools\ffprobe.exe'
                New-Item -Path $ffprobeConfigPath -ItemType File -Force | Out-Null

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = 'tools\ffprobe.exe'; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfprobeExePath | Should -Be $ffprobeConfigPath
                # 交叉校验：只配置 ffprobe 时其余两个工具不应被污染
                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - PATH 环境变量回退（L4）' {
        It '配置路径为空时应回退到 PATH 查找（ffmpeg）' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Source = 'C:\ffmpeg\bin\ffmpeg.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be 'C:\ffmpeg\bin\ffmpeg.exe'
            }
        }

        It '配置路径为空时应回退到 PATH 查找（ffprobe）' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffprobe' } {
                    return [PSCustomObject]@{ Source = 'C:\ffmpeg\bin\ffprobe.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfprobeExePath | Should -Be 'C:\ffmpeg\bin\ffprobe.exe'
            }
        }
    }

    Context '构造函数 - 工具未找到（L3）' {
        It '配置路径不存在且 PATH 中也找不到时 ffmpeg 应为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = 'nonexistent\ffmpeg.exe'; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
            }
        }

        It '配置路径不存在且 PATH 中也找不到时 ffprobe 应为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = 'nonexistent\ffprobe.exe'; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
            }
        }

        It 'realcugan 配置路径不存在且 bin 目录中也找不到时应为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = 'nonexistent\realcugan.exe' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }

        It 'Get-Command 命中但没有 Source 时应返回空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                # 模拟命令被解析成函数/别名：对象存在但 Source 为空
                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Name = 'ffmpeg' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - Real-CUGAN 路径解析（L1/L4）' {
        It '配置路径存在时应使用配置路径' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $realcuganConfigPath = Join-Path $p 'tools\realcugan.exe'
                New-Item -Path $realcuganConfigPath -ItemType File -Force | Out-Null

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = 'tools\realcugan.exe' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -Be $realcuganConfigPath
            }
        }

        It '配置路径为空时应在 bin 目录中递归查找 realcugan-ncnn-vulkan.exe' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $binPath = Join-Path $p 'bin'
                $nestedDir = Join-Path $binPath 'nested\deep'
                New-Item -Path $nestedDir -ItemType Directory -Force | Out-Null
                # 放到二级子目录，证明 -Recurse 与相对路径拼接都生效
                $realcuganExe = Join-Path $nestedDir 'realcugan-ncnn-vulkan.exe'
                New-Item -Path $realcuganExe -ItemType File -Force | Out-Null

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -Be $realcuganExe
                # 交叉校验：bin 查找只影响 realcugan
                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
            }
        }

        It '配置路径指向目录时应视为未命中并在 bin 目录中查找' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path (Join-Path $p 'tools') -ItemType Directory -Force | Out-Null
                $binPath = Join-Path $p 'bin'
                New-Item -Path $binPath -ItemType Directory -Force | Out-Null
                $realcuganExe = Join-Path $binPath 'realcugan-ncnn-vulkan.exe'
                New-Item -Path $realcuganExe -ItemType File -Force | Out-Null

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = 'tools' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -Be $realcuganExe
                # 交叉校验：目录配置被拒绝后只影响 realcugan
                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - 配置路径存在但文件实际不存在（L4）' {
        It '配置路径指定但文件不存在时应回退到 PATH 查找' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Source = 'C:\tools\ffmpeg.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = 'bin\ffmpeg.exe'; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be 'C:\tools\ffmpeg.exe'
            }
        }
    }

    Context '构造函数 - 配置路径指向目录（L3）' {
        It '配置路径指向目录时应视为未命中并回退到 PATH 查找' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path (Join-Path $p 'tools') -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Source = 'C:\tools\ffmpeg.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = 'tools'; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be 'C:\tools\ffmpeg.exe'
                # 交叉校验：目录配置被拒绝后其余两个工具不应被污染
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - settings 缺失或为空（L2）' {
        It 'settings 为 null 时三个路径均为空（构造完成即证明未抛系统异常）' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $toolConfig = [ToolConfiguration]::new($pathConfig, $null)

                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }

        It 'settings 中缺少 paths 键时三个路径均为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $toolConfig = [ToolConfiguration]::new($pathConfig, @{})

                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - PathConfig 为空（L2）' {
        It 'PathConfig 为 null 时应抛出 ArgumentException 而非系统异常' {
            InModuleScope IPAP {
                { [ToolConfiguration]::new($null, @{}) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage 'PathConfig 不能为空'
            }
        }
    }

    Context '构造函数 - settings.paths 类型非法（L2）' {
        It 'paths 为字符串时应抛出 ArgumentException' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $pathConfig = [PathConfiguration]::new($p, $null, $null)

                { [ToolConfiguration]::new($pathConfig, @{ paths = 'abc' }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'paths' 必须是 IDictionary 类型，当前值类型为 'String'"
            }
        }

        It 'paths 为整数时应抛出 ArgumentException' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $pathConfig = [PathConfiguration]::new($p, $null, $null)

                { [ToolConfiguration]::new($pathConfig, @{ paths = 42 }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'paths' 必须是 IDictionary 类型，当前值类型为 'Int32'"
            }
        }

        It 'paths 为数组时应抛出 ArgumentException' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $pathConfig = [PathConfiguration]::new($p, $null, $null)

                # 消息含 '[]'，-ExpectedMessage 按通配符解析，方括号必须用反引号转义
                { [ToolConfiguration]::new($pathConfig, @{ paths = @('a') }) } |
                    Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "配置项 'paths' 必须是 IDictionary 类型，当前值类型为 'Object``[``]'"
            }
        }
    }

    Context '构造函数验证（L1）' {
        It '应返回 ToolConfiguration 实例' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig | Should -BeOfType 'ToolConfiguration'
            }
        }
    }

    Context '属性类型验证（L5）' {
        It '所有公开属性应为 string 类型' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -BeOfType [string]
                $toolConfig.FfmpegExePath | Should -BeOfType [string]
                $toolConfig.FfprobeExePath | Should -BeOfType [string]
            }
        }
    }

    Context '边界情况 - 多工具混合状态（L3）' {
        It '部分工具找到部分未找到时应正确反映各自状态' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Source = 'C:\tools\ffmpeg.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be 'C:\tools\ffmpeg.exe'
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }

        It '所有工具都找到时应返回各自的正确路径' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                $binPath = Join-Path $p 'bin'
                New-Item -Path $binPath -ItemType Directory -Force | Out-Null
                $realcuganExe = Join-Path $binPath 'realcugan-ncnn-vulkan.exe'
                New-Item -Path $realcuganExe -ItemType File -Force | Out-Null

                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Source = 'C:\tools\ffmpeg.exe' }
                }
                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffprobe' } {
                    return [PSCustomObject]@{ Source = 'C:\tools\ffprobe.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be 'C:\tools\ffmpeg.exe'
                $toolConfig.FfprobeExePath | Should -Be 'C:\tools\ffprobe.exe'
                $toolConfig.RealCuganExePath | Should -Be $realcuganExe
            }
        }
    }

    Context '边界情况 - settings 结构不完整（L3）' {
        It 'settings.paths 为 null 时应回退为空配置而非抛异常' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = $null }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                # 构造完成即证明未抛系统异常；三个字段同时验证 null 区块被当作空配置
                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }

        It 'settings.paths 中缺少某些键时应使用默认空值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{} }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }
    }

    Context '边界情况 - 配置值为纯空白（L3）' {
        It '配置值为纯空白时应视为空并回退到 PATH 查找' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'

                Mock -CommandName Get-Command -ModuleName IPAP -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Source = 'C:\ffmpeg\bin\ffmpeg.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = '   '; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be 'C:\ffmpeg\bin\ffmpeg.exe'
            }
        }
    }
}
