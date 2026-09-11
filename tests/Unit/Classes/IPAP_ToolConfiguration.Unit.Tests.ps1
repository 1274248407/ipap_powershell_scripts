#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - ToolConfiguration 单元测试
.DESCRIPTION
    测试 ToolConfiguration 类的构造函数、工具路径解析逻辑（ResolveToolPath / ResolveRealCuganPath）
    和静态工厂方法 Load。使用真实目录和文件替代全局 Mock Test-Path，避免干扰
    PathConfiguration 构造函数中的目录验证。
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

    Context '构造函数 - 配置路径优先' {
        It '当配置路径存在时应使用配置路径（ffmpeg）' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $ffmpegConfigPath = Join-Path $p 'tools\ffmpeg.exe'
                New-Item -Path $ffmpegConfigPath -ItemType File -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = 'tools\ffmpeg.exe'; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be $ffmpegConfigPath
            }
        }

        It '当配置路径存在时应使用配置路径（ffprobe）' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $ffprobeConfigPath = Join-Path $p 'tools\ffprobe.exe'
                New-Item -Path $ffprobeConfigPath -ItemType File -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = 'tools\ffprobe.exe'; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfprobeExePath | Should -Be $ffprobeConfigPath
            }
        }
    }

    Context '构造函数 - PATH 环境变量回退' {
        It '配置路径为空时应回退到 PATH 查找（ffmpeg）' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ffmpeg' } {
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
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ffprobe' } {
                    return [PSCustomObject]@{ Source = 'C:\ffmpeg\bin\ffprobe.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfprobeExePath | Should -Be 'C:\ffmpeg\bin\ffprobe.exe'
            }
        }
    }

    Context '构造函数 - 工具未找到' {
        It '配置路径不存在且 PATH 中也找不到时 ffmpeg 应为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = 'nonexistent\ffmpeg.exe'; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
            }
        }

        It '配置路径不存在且 PATH 中也找不到时 ffprobe 应为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = 'nonexistent\ffprobe.exe'; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
            }
        }

        It 'realcugan 配置路径不存在且 bin 目录中也找不到时应为空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = 'nonexistent\realcugan.exe' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - Real-CUGAN 路径解析' {
        It '配置路径存在时应使用配置路径' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $realcuganConfigPath = Join-Path $p 'tools\realcugan.exe'
                New-Item -Path $realcuganConfigPath -ItemType File -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = 'tools\realcugan.exe' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -Be $realcuganConfigPath
            }
        }

        It '配置路径为空时应在 bin 目录中递归查找 realcugan-ncnn-vulkan.exe' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $binPath = Join-Path $p 'bin'
                New-Item -Path $binPath -ItemType Directory -Force | Out-Null
                $realcuganExe = Join-Path $binPath 'realcugan-ncnn-vulkan.exe'
                New-Item -Path $realcuganExe -ItemType File -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context '构造函数 - 配置路径存在但文件实际不存在' {
        It '配置路径指定但文件不存在时应回退到 PATH 查找' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Source = 'C:\tools\ffmpeg.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = 'bin\ffmpeg.exe'; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Be 'C:\tools\ffmpeg.exe'
            }
        }
    }

    Context '构造函数验证' {
        It '应返回 ToolConfiguration 实例' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig | Should -BeOfType 'ToolConfiguration'
            }
        }
    }

    Context '属性类型验证' {
        It '所有公开属性应为 string 类型' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.RealCuganExePath | Should -BeOfType [string]
                $toolConfig.FfmpegExePath | Should -BeOfType [string]
                $toolConfig.FfprobeExePath | Should -BeOfType [string]
            }
        }
    }

    Context '边界情况 - 多工具混合状态' {
        It '部分工具找到部分未找到时应正确反映各自状态' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ffmpeg' } {
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

        It '所有工具都找到时应全部非空' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null
                $binPath = Join-Path $p 'bin'
                New-Item -Path $binPath -ItemType Directory -Force | Out-Null
                $realcuganExe = Join-Path $binPath 'realcugan-ncnn-vulkan.exe'
                New-Item -Path $realcuganExe -ItemType File -Force | Out-Null

                Mock -CommandName Get-Command { return $null }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ffmpeg' } {
                    return [PSCustomObject]@{ Source = 'C:\tools\ffmpeg.exe' }
                }
                Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'ffprobe' } {
                    return [PSCustomObject]@{ Source = 'C:\tools\ffprobe.exe' }
                }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{ ffmpeg_exe = ''; ffprobe_exe = ''; realcugan_exe = '' } }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -Not -BeNullOrEmpty
                $toolConfig.FfprobeExePath | Should -Not -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context '边界情况 - settings 结构不完整' {
        It 'settings.paths 为 null 时不应抛出异常' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = $null }
                { [ToolConfiguration]::new($pathConfig, $settings) } | Should -Not -Throw
            }
        }

        It 'settings.paths 中缺少某些键时应使用默认空值' {
            InModuleScope IPAP {
                $p = Join-Path $TestDrive 'MockProject'
                New-Item -Path $p -ItemType Directory -Force | Out-Null

                Mock -CommandName Get-Command { return $null }

                $pathConfig = [PathConfiguration]::new($p, $null, $null)
                $settings = @{ paths = @{} }
                $toolConfig = [ToolConfiguration]::new($pathConfig, $settings)

                $toolConfig.FfmpegExePath | Should -BeNullOrEmpty
                $toolConfig.FfprobeExePath | Should -BeNullOrEmpty
                $toolConfig.RealCuganExePath | Should -BeNullOrEmpty
            }
        }
    }
}
