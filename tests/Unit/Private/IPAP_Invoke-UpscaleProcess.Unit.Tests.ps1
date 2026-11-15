#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Invoke-UpscaleProcess 单元测试
.DESCRIPTION
    按 docs/单元测试方法论.md 的 L1-L5 覆盖单图执行器：
    - L1 成功路径：RealCugan / FFmpeg 各自的成功判据
    - L2 异常路径：进程调用抛异常时捕获并返回失败与错误消息（catch 分支）
    - L3 边界数据：退出码 0/非 0、输出文件存在/不存在、空 exe 路径
    - L4 分支覆盖：引擎二选一分支（同一输入下 RealCugan 与 FFmpeg 结论互斥），
      catch 分支由 L2 用例覆盖
    - L5 输出字段：Success / Image / Error 三字段与类型
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
                [ValidateSet('RealCugan', 'FFmpeg', 'Webp')]
                [string]$Engine,
                [string]$OutputPath,
                [scriptblock]$FakeProcess,
                [string]$ExePath = 'fake-exe',
                [string]$ImagePath = 'C:\src\a.jpg',
                [switch]$CopyOriginalOnFailure
            )
            InModuleScope IPAP -Parameters @{
                EngineName = $Engine
                OutPath    = $OutputPath
                Fake       = $FakeProcess
                Exe        = $ExePath
                SrcPath    = $ImagePath
                Fallback   = [bool]$CopyOriginalOnFailure
            } -ScriptBlock {
                param($EngineName, $OutPath, $Fake, $Exe, $SrcPath, $Fallback)
                $image = [PSCustomObject]@{ Name = (Split-Path -Path $SrcPath -Leaf); FullName = $SrcPath }
                return Invoke-UpscaleProcess -Image $image -OutputPath $OutPath `
                    -Arguments @('-i', $SrcPath, '-o', $OutPath) `
                    -Engine $EngineName -ExePath $Exe -CopyOriginalOnFailure:$Fallback -InvokeProcess $Fake
            }
        }

        function Invoke-ProcessDefaultAdapter {
            [CmdletBinding()]
            param(
                [ValidateSet('RealCugan', 'FFmpeg', 'Webp')]
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
                $image = [PSCustomObject]@{ Name = 'a.jpg'; FullName = 'C:\src\a.jpg' }
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

    Context 'L4 分支覆盖' {
        It '同一输入（退出码 1 且输出文件存在）下 RealCugan 与 FFmpeg 的判定分支应互斥' {
            [string]$outputPath = Join-Path $TestDrive 'engine-branch.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $realCuganResult = Invoke-ProcessTest -Engine 'RealCugan' -OutputPath $outputPath -FakeProcess { param($P, $A) return 1 }
            $ffmpegResult = Invoke-ProcessTest -Engine 'FFmpeg' -OutputPath $outputPath -FakeProcess { param($P, $A) return 1 }

            $realCuganResult.Success | Should -BeTrue
            $ffmpegResult.Success | Should -BeFalse
        }
    }

    Context 'L1 默认适配器（真实进程调用边界）' {
        BeforeAll {
            # 用系统命令解释器作为无害替身，避免依赖真实 RealCugan / FFmpeg
            [string]$script:CommandShell = $env:ComSpec
        }

        It 'RealCugan 默认适配器应重定向并丢弃输出后返回退出码 0 判定成功' {
            [string]$outputPath = Join-Path $TestDrive 'default-rc-ok.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessDefaultAdapter -Engine 'RealCugan' -OutputPath $outputPath `
                -ProcessArguments @('/c', 'exit', '0') -ExePath $CommandShell

            $result.Success | Should -BeTrue
            $result.Image | Should -Be 'a.jpg'
            $result.Error | Should -Be ''
        }

        It 'Stop 模式下命令写 stderr 不应中断处理' {
            [string]$outputPath = Join-Path $TestDrive 'default-stderr-stop.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = InModuleScope IPAP -Parameters @{
                Out    = $outputPath
                Exe    = $CommandShell
                Engine = 'RealCugan'
            } -ScriptBlock {
                param($Out, $Exe, $Engine)
                $previous = $ErrorActionPreference
                $ErrorActionPreference = 'Stop'
                try {
                    $image = [PSCustomObject]@{ Name = 'a.jpg' }
                    Invoke-UpscaleProcess -Image $image -OutputPath $Out `
                        -Arguments @('/c', 'echo noise 1>&2 & exit 0') `
                        -Engine $Engine -ExePath $Exe
                }
                finally {
                    $ErrorActionPreference = $previous
                }
            }

            $result.Success | Should -BeTrue
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

    Context 'L1/L4 Webp 转码引擎与失败兜底' {
        BeforeEach {
            # 源与输出分居两个目录，才能真实观察「把原图复制到输出目录」
            $script:SrcDir = Join-Path $TestDrive 'src'
            $script:OutDir = Join-Path $TestDrive 'out'
            foreach ($dir in @($script:SrcDir, $script:OutDir)) {
                if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
                $null = New-Item -ItemType Directory -Path $dir -Force
            }
        }

        It 'Webp 引擎退出码 0 且输出存在时应返回 Success=true' {
            [string]$outputPath = Join-Path $script:OutDir 'webp-ok.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessTest -Engine 'Webp' -OutputPath $outputPath -FakeProcess { param($P, $A) return 0 }

            $result.Success | Should -BeTrue
            $result.Error | Should -Be ''
        }

        It 'Webp 引擎与 FFmpeg 使用同一成功判据（退出码非 0 即失败）' {
            [string]$outputPath = Join-Path $script:OutDir 'webp-exit1.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $result = Invoke-ProcessTest -Engine 'Webp' -OutputPath $outputPath -FakeProcess { param($P, $A) return 1 }

            $result.Success | Should -BeFalse
        }

        It '转码失败时应把原图复制到输出目录并保留原扩展名' {
            [string]$sourcePath = Join-Path $script:SrcDir 'src-page.jpg'
            [IO.File]::WriteAllBytes($sourcePath, [byte[]]::new(42))
            [string]$outputPath = Join-Path $script:OutDir 'src-page.webp'

            $result = Invoke-ProcessTest -Engine 'Webp' -OutputPath $outputPath -ImagePath $sourcePath `
                -CopyOriginalOnFailure -FakeProcess { param($P, $A) return 1 }

            $result.Success | Should -BeFalse
            $fallbackPath = Join-Path $script:OutDir 'src-page.jpg'
            (Test-Path -LiteralPath $fallbackPath) | Should -BeTrue
            (Get-Item -LiteralPath $fallbackPath).Length | Should -Be 42
            (Test-Path -LiteralPath $outputPath) | Should -BeFalse
        }

        It '失败时残留的 0 字节输出应先清除，避免目录里多出一页' {
            [string]$sourcePath = Join-Path $script:SrcDir 'partial-page.jpg'
            [IO.File]::WriteAllBytes($sourcePath, [byte[]]::new(42))
            [string]$outputPath = Join-Path $script:OutDir 'partial-page.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(0))

            $result = Invoke-ProcessTest -Engine 'Webp' -OutputPath $outputPath -ImagePath $sourcePath `
                -CopyOriginalOnFailure -FakeProcess { param($P, $A) return 1 }

            $result.Success | Should -BeFalse
            (Test-Path -LiteralPath $outputPath) | Should -BeFalse
            @(Get-ChildItem -LiteralPath $script:OutDir -File).Count | Should -Be 1
            (Test-Path -LiteralPath (Join-Path $script:OutDir 'partial-page.jpg')) | Should -BeTrue
        }

        It '转码成功时不应复制原图' {
            [string]$sourcePath = Join-Path $script:SrcDir 'ok-page.jpg'
            [IO.File]::WriteAllBytes($sourcePath, [byte[]]::new(42))
            [string]$outputPath = Join-Path $script:OutDir 'ok-page.webp'
            [IO.File]::WriteAllBytes($outputPath, [byte[]]::new(10))

            $null = Invoke-ProcessTest -Engine 'Webp' -OutputPath $outputPath -ImagePath $sourcePath `
                -CopyOriginalOnFailure -FakeProcess { param($P, $A) return 0 }

            @(Get-ChildItem -LiteralPath $script:OutDir -File).Count | Should -Be 1
            @(Get-ChildItem -LiteralPath $script:OutDir -File -Filter '*.jpg').Count | Should -Be 0
        }

        It '进程调用抛异常时也应先兜底复制原图再返回失败' {
            [string]$sourcePath = Join-Path $script:SrcDir 'throw-page.png'
            [IO.File]::WriteAllBytes($sourcePath, [byte[]]::new(7))
            [string]$outputPath = Join-Path $script:OutDir 'throw-page.webp'

            $result = Invoke-ProcessTest -Engine 'Webp' -OutputPath $outputPath -ImagePath $sourcePath `
                -CopyOriginalOnFailure -FakeProcess { param($P, $A) throw 'boom' }

            $result.Success | Should -BeFalse
            $result.Error | Should -Be 'boom'
            (Test-Path -LiteralPath (Join-Path $script:OutDir 'throw-page.png')) | Should -BeTrue
        }

        It '兜底复制原图也失败时应在 Error 中追加原因' {
            [string]$sourcePath = Join-Path $script:SrcDir 'missing-source.jpg'
            [string]$outputPath = Join-Path $script:OutDir 'missing-source.webp'

            $result = Invoke-ProcessTest -Engine 'Webp' -OutputPath $outputPath -ImagePath $sourcePath `
                -CopyOriginalOnFailure -FakeProcess { param($P, $A) return 1 }

            $result.Success | Should -BeFalse
            $result.Error | Should -BeLike '*回退复制原图失败*'
        }

        It '未指定 -CopyOriginalOnFailure 时失败不应产生任何文件' {
            [string]$sourcePath = Join-Path $script:SrcDir 'nofallback.jpg'
            [IO.File]::WriteAllBytes($sourcePath, [byte[]]::new(5))
            [string]$outputPath = Join-Path $script:OutDir 'nofallback.webp'

            $result = Invoke-ProcessTest -Engine 'Webp' -OutputPath $outputPath -ImagePath $sourcePath `
                -FakeProcess { param($P, $A) return 1 }

            $result.Success | Should -BeFalse
            @(Get-ChildItem -LiteralPath $script:OutDir -File).Count | Should -Be 0
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
