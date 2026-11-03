#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Invoke-UpscaleProcess 单元测试
.DESCRIPTION
    按 doc/单元测试方法论.md 覆盖单图执行器：
    L1 成功路径、L2 异常路径、L3 引擎成功判据边界、L5 输出字段。
    外部进程通过 -InvokeProcess 注入假实现，不依赖真实引擎；
    默认适配器属进程调用边界，用系统 cmd.exe 作为无害替身覆盖
    重定向/不重定向、退出码 0/非 0、命令不存在三条路径。
#>

Describe 'Invoke-UpscaleProcess Unit Tests' -Tag 'Invoke-UpscaleProcess', 'IPAP' {
    BeforeAll {
        $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $script:ProjectRoot 'source\IPAP.psd1') -Force -Global

        function Invoke-ProcessTest {
            [CmdletBinding()]
            param(
                [ValidateSet('RealCugan', 'FFmpeg')]
                [string]$Engine,
                [string]$OutputPath,
                [scriptblock]$FakeProcess,
                [string]$ExePath = 'fake-exe'
            )
            InModuleScope IPAP -Parameters @{
                EngineName = $Engine
                OutPath    = $OutputPath
                Fake       = $FakeProcess
                Exe        = $ExePath
            } -ScriptBlock {
                param($EngineName, $OutPath, $Fake, $Exe)
                $image = [PSCustomObject]@{ Name = 'a.jpg' }
                return Invoke-UpscaleProcess -Image $image -OutputPath $OutPath `
                    -Arguments @('-i', 'a.jpg', '-o', $OutPath) `
                    -Engine $EngineName -ExePath $Exe -InvokeProcess $Fake
            }
        }

        function Invoke-ProcessDefaultAdapter {
            [CmdletBinding()]
            param(
                [ValidateSet('RealCugan', 'FFmpeg')]
                [string]$Engine,
                [string]$OutputPath,
                [string[]]$ProcessArguments,
                [string]$ExePath
            )
            InModuleScope IPAP -Parameters @{
                EngineName = $Engine
                OutPath    = $OutputPath
                ProcArgs   = $ProcessArguments
                Exe        = $ExePath
            } -ScriptBlock {
                param($EngineName, $OutPath, $ProcArgs, $Exe)
                $image = [PSCustomObject]@{ Name = 'a.jpg' }
                return Invoke-UpscaleProcess -Image $image -OutputPath $OutPath `
                    -Arguments $ProcArgs -Engine $EngineName -ExePath $Exe
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context 'L1 RealCugan 成功路径' {
        It '输出文件存在时应返回 Success=true' {
            [string]$outputPath = Join-Path $TestDrive 'rc-ok.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessTest -Engine 'RealCugan' -OutputPath $outputPath -FakeProcess { param($P, $A) return 0 }

            $result.Success | Should -BeTrue
            $result.Image | Should -Be 'a.jpg'
            $result.Error | Should -Be ''
        }

        It 'RealCugan 应忽略退出码，只看输出文件是否存在' {
            [string]$outputPath = Join-Path $TestDrive 'rc-ignore-exit.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessTest -Engine 'RealCugan' -OutputPath $outputPath -FakeProcess { param($P, $A) return -1 }

            $result.Success | Should -BeTrue
        }
    }

    Context 'L3 成功判据边界' {
        It 'RealCugan 输出文件不存在时应返回 Success=false' {
            [string]$outputPath = Join-Path $TestDrive 'rc-missing.webp'

            $result = Invoke-ProcessTest -Engine 'RealCugan' -OutputPath $outputPath -FakeProcess { param($P, $A) return 0 }

            $result.Success | Should -BeFalse
            $result.Error | Should -Be ''
        }

        It 'FFmpeg 退出码非 0 时应返回 Success=false' {
            [string]$outputPath = Join-Path $TestDrive 'ffmpeg-exit1.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessTest -Engine 'FFmpeg' -OutputPath $outputPath -FakeProcess { param($P, $A) return 1 }

            $result.Success | Should -BeFalse
        }

        It 'FFmpeg 退出码为 0 但输出文件不存在时应返回 Success=false' {
            [string]$outputPath = Join-Path $TestDrive 'ffmpeg-missing.webp'

            $result = Invoke-ProcessTest -Engine 'FFmpeg' -OutputPath $outputPath -FakeProcess { param($P, $A) return 0 }

            $result.Success | Should -BeFalse
        }
    }

    Context 'L1 FFmpeg 成功路径' {
        It '退出码为 0 且输出文件存在时应返回 Success=true' {
            [string]$outputPath = Join-Path $TestDrive 'ffmpeg-ok.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessTest -Engine 'FFmpeg' -OutputPath $outputPath -FakeProcess { param($P, $A) return 0 }

            $result.Success | Should -BeTrue
            $result.Image | Should -Be 'a.jpg'
            $result.Error | Should -Be ''
        }
    }

    Context 'L2 异常路径' {
        It 'RealCugan 进程调用抛异常时应返回 Success=false 并保留消息' {
            [string]$outputPath = Join-Path $TestDrive 'rc-throw.webp'

            $result = Invoke-ProcessTest -Engine 'RealCugan' -OutputPath $outputPath -FakeProcess { param($P, $A) throw 'boom' }

            $result.Success | Should -BeFalse
            $result.Error | Should -Be 'boom'
        }

        It 'FFmpeg 进程调用抛异常时应返回 Success=false 并保留消息' {
            [string]$outputPath = Join-Path $TestDrive 'ffmpeg-throw.webp'

            $result = Invoke-ProcessTest -Engine 'FFmpeg' -OutputPath $outputPath -FakeProcess { param($P, $A) throw 'boom' }

            $result.Success | Should -BeFalse
            $result.Error | Should -Be 'boom'
        }
    }

    Context 'L1 默认适配器（真实进程调用边界）' {
        BeforeAll {
            # 用系统命令解释器作为无害替身，避免依赖真实 RealCugan / FFmpeg
            [string]$script:CommandShell = $env:ComSpec
        }

        It 'RealCugan 默认适配器应不重定向输出并返回退出码 0 判定成功' {
            [string]$outputPath = Join-Path $TestDrive 'default-rc-ok.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessDefaultAdapter -Engine 'RealCugan' -OutputPath $outputPath `
                -ProcessArguments @('/c', 'exit', '0') -ExePath $CommandShell

            $result.Success | Should -BeTrue
            $result.Image | Should -Be 'a.jpg'
            $result.Error | Should -Be ''
        }

        It 'FFmpeg 默认适配器应捕获输出并返回退出码 0 判定成功' {
            [string]$outputPath = Join-Path $TestDrive 'default-ffmpeg-ok.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessDefaultAdapter -Engine 'FFmpeg' -OutputPath $outputPath `
                -ProcessArguments @('/c', 'exit', '0') -ExePath $CommandShell

            $result.Success | Should -BeTrue
        }

        It 'FFmpeg 默认适配器退出码非 0 时应判定失败' {
            [string]$outputPath = Join-Path $TestDrive 'default-ffmpeg-fail.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessDefaultAdapter -Engine 'FFmpeg' -OutputPath $outputPath `
                -ProcessArguments @('/c', 'exit', '1') -ExePath $CommandShell

            $result.Success | Should -BeFalse
            $result.Error | Should -Be ''
        }

        It '默认适配器命令不存在时应捕获异常并返回失败与错误消息' {
            [string]$outputPath = Join-Path $TestDrive 'default-missing.webp'

            $result = Invoke-ProcessDefaultAdapter -Engine 'FFmpeg' -OutputPath $outputPath `
                -ProcessArguments @('-i', 'a.jpg') -ExePath 'C:\nope\missing-engine.exe'

            $result.Success | Should -BeFalse
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'L5 输出字段' {
        It '结果对象应包含 Success / Image / Error 三个字段' {
            [string]$outputPath = Join-Path $TestDrive 'fields.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessTest -Engine 'RealCugan' -OutputPath $outputPath -FakeProcess { param($P, $A) return 0 }

            @($result.PSObject.Properties.Name | Sort-Object) |
                Should -Be @('Error', 'Image', 'Success')
            ($result.Success -is [bool]) | Should -BeTrue
            $result.Image | Should -BeOfType [string]
        }
    }
}
