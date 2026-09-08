#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Invoke-ParallelUpscale 单元测试
.DESCRIPTION
    测试 Invoke-ParallelUpscale 函数的并行处理逻辑。
    注意：单元测试 Mock 掉 ForEach-Object -Parallel，仅验证参数校验和核心逻辑。
#>

Describe 'Invoke-ParallelUpscale Unit Tests' -Tag 'Invoke-ParallelUpscale', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        # 使用全局 Mock（Write-ErrorLog 模拟真实 throw 语义）
        Mock -ModuleName IPAP Write-InfoLog {}
        Mock -ModuleName IPAP Write-WarningLog {}
        Mock -ModuleName IPAP Write-ErrorLog { param($Message) throw $Message }
        Mock -ModuleName IPAP Test-Path { return $false }
        Mock -ModuleName IPAP New-Item {}
        Mock -ModuleName IPAP Get-ChildItem {}
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '引擎可执行文件缺失处理' {
        It 'RealCugan 引擎且 Get-RealCuganExePath 找不到时应抛出终止错误' {
            Mock -ModuleName IPAP Get-RealCuganExePath { throw '未找到 Real-CUGAN' }
            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )

            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' } | Should -Throw '未找到 Real-CUGAN*'
        }

        It 'FFmpeg 引擎且 Get-FfmpegPath 找不到时应抛出终止错误' {
            Mock -ModuleName IPAP Get-FfmpegPath { throw '未找到 FFmpeg' }
            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )

            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -Engine 'FFmpeg' } | Should -Throw '未找到 FFmpeg*'
        }

        It 'exe 路径为空时单张图片应计入失败计数' {
            # Get-RealCuganExePath 返回空路径时源码不抛出，并行块内执行失败计入 FailedCount
            Mock -ModuleName IPAP Get-RealCuganExePath { return $null }
            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )

            $result = Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1

            $result.SuccessCount | Should -Be 0
            $result.FailedCount | Should -Be 1
        }
    }

    Context '输出目录处理' {
        BeforeEach {
            Mock -ModuleName IPAP Get-RealCuganExePath { return 'C:\bin\realcugan-ncnn-vulkan.exe' }
            Mock -ModuleName IPAP ForEach-Object { return @{ Success = $true; Image = 'test.jpg' } }
        }

        It '输出目录不存在时应创建' {
            Mock -ModuleName IPAP Test-Path -RemoveParameterType 'Path', 'LiteralPath' {
                param($LiteralPath)
                if ($LiteralPath -match 'output') { return $false }
                return $true
            }

            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )

            Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1

            Should -Invoke -ModuleName IPAP New-Item -Times 1
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        It '函数应有 Mandatory 参数 Images' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['Images']
            $param.Attributes.Mandatory | Should -Be $true
        }

        It '函数应有 Mandatory 参数 OutputDir' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['OutputDir']
            $param.Attributes.Mandatory | Should -Be $true
        }
    }

    Context '参数定义验证 - Parameter Definition' {
        It 'MaxWorkers 参数应使用 ValidateRange(1, 32)' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['MaxWorkers']
            $rangeAttr = $param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateRangeAttribute' }

            $rangeAttr.MinRange | Should -Be 1
            $rangeAttr.MaxRange | Should -Be 32
        }

        It 'Scale 参数应使用 ValidateRange(1, 4)' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['Scale']
            $rangeAttr = $param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateRangeAttribute' }

            $rangeAttr.MinRange | Should -Be 1
            $rangeAttr.MaxRange | Should -Be 4
        }

        It 'NoiseLevel 参数应使用 ValidateRange(-1, 3)' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['NoiseLevel']
            $rangeAttr = $param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateRangeAttribute' }

            $rangeAttr.MinRange | Should -Be -1
            $rangeAttr.MaxRange | Should -Be 3
        }

        It 'TileSize 参数应使用 ValidateRange(32, 1024)' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['TileSize']
            $rangeAttr = $param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateRangeAttribute' }

            $rangeAttr.MinRange | Should -Be 32
            $rangeAttr.MaxRange | Should -Be 1024
        }

        It 'ModelPath 参数应使用 ValidateSet' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['ModelPath']
            $setAttr = $param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateSetAttribute' }

            $setAttr.ValidValues | Should -Contain 'models-se'
            $setAttr.ValidValues | Should -Contain 'models-pro'
            $setAttr.ValidValues | Should -Contain 'models-nose'
        }

        It 'OutputFormat 参数应使用 ValidateSet' {
            $cmd = Get-Command Invoke-ParallelUpscale
            $param = $cmd.Parameters['OutputFormat']
            $setAttr = $param.Attributes | Where-Object { $PSItem.GetType().Name -eq 'ValidateSetAttribute' }

            $setAttr.ValidValues | Should -Contain 'jpg'
            $setAttr.ValidValues | Should -Contain 'png'
            $setAttr.ValidValues | Should -Contain 'webp'
        }
    }

    Context '参数行为测试 - Parameter Behavior' {
        BeforeEach {
            Mock -ModuleName IPAP Get-RealCuganExePath { return 'C:\bin\realcugan-ncnn-vulkan.exe' }
            Mock -ModuleName IPAP Test-Path -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock -ModuleName IPAP ForEach-Object { return @{ Success = $true; Image = 'test.jpg' } }
        }

        It 'Scale 参数应接受边界值 1' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -Scale 1 } | Should -Not -Throw
        }

        It 'Scale 参数应接受边界值 4' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -Scale 4 } | Should -Not -Throw
        }

        It 'Scale 参数应拒绝小于 1 的值' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -Scale 0 } | Should -Throw
        }

        It 'Scale 参数应拒绝大于 4 的值' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -Scale 5 } | Should -Throw
        }

        It 'NoiseLevel 参数应接受边界值 -1' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -NoiseLevel -1 } | Should -Not -Throw
        }

        It 'NoiseLevel 参数应接受边界值 3' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -NoiseLevel 3 } | Should -Not -Throw
        }

        It 'NoiseLevel 参数应拒绝小于 -1 的值' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -NoiseLevel -2 } | Should -Throw
        }

        It 'NoiseLevel 参数应拒绝大于 3 的值' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -NoiseLevel 4 } | Should -Throw
        }

        It 'TileSize 参数应接受边界值 32' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -TileSize 32 } | Should -Not -Throw
        }

        It 'TileSize 参数应接受边界值 1024' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -TileSize 1024 } | Should -Not -Throw
        }

        It 'TileSize 参数应拒绝小于 32 的值' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -TileSize 31 } | Should -Throw
        }

        It 'MaxWorkers 参数应接受边界值 1' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 } | Should -Not -Throw
        }

        It 'MaxWorkers 参数应接受边界值 32' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 32 } | Should -Not -Throw
        }

        It 'MaxWorkers 参数应拒绝小于 1 的值' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 0 } | Should -Throw
        }

        It 'ModelPath 参数应接受有效值 models-se' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -ModelPath 'models-se' } | Should -Not -Throw
        }

        It 'ModelPath 参数应接受有效值 models-pro' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -ModelPath 'models-pro' } | Should -Not -Throw
        }

        It 'ModelPath 参数应接受有效值 models-nose' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -ModelPath 'models-nose' } | Should -Not -Throw
        }

        It 'ModelPath 参数应拒绝无效值' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -ModelPath 'invalid-model' } | Should -Throw
        }

        It 'OutputFormat 参数应接受有效值 jpg' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -OutputFormat 'jpg' } | Should -Not -Throw
        }

        It 'OutputFormat 参数应接受有效值 png' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -OutputFormat 'png' } | Should -Not -Throw
        }

        It 'OutputFormat 参数应接受有效值 webp' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -OutputFormat 'webp' } | Should -Not -Throw
        }

        It 'OutputFormat 参数应拒绝无效值' {
            $mockImages = @([PSCustomObject]@{ Name = 'test.jpg'; FullName = 'C:\test.jpg' })
            { Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1 -OutputFormat 'gif' } | Should -Throw
        }
    }

    Context '返回值结构测试' {
        BeforeEach {
            Mock -ModuleName IPAP Get-RealCuganExePath { return 'C:\bin\realcugan-ncnn-vulkan.exe' }
            Mock -ModuleName IPAP Test-Path -RemoveParameterType 'Path', 'LiteralPath' { return $true }
        }

        It '应返回包含 SuccessCount 和 FailedCount 的哈希表' {
            Mock -ModuleName IPAP ForEach-Object { return @{ Success = $true; Image = 'test1.jpg' } }

            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\test1.jpg' }
            )

            $result = Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\output' -MaxWorkers 1

            $result | Should -BeOfType [hashtable]
            $result.Keys | Should -Contain 'SuccessCount'
            $result.Keys | Should -Contain 'FailedCount'
        }
    }

    Context '边界值测试 - Boundary Value' {
        BeforeEach {
            Mock -ModuleName IPAP Get-RealCuganExePath { return 'C:\bin\realcugan-ncnn-vulkan.exe' }
            Mock -ModuleName IPAP Test-Path -RemoveParameterType 'Path', 'LiteralPath' { return $true }
            Mock -ModuleName IPAP ForEach-Object { return @{ Success = $true; Image = 'test1.jpg' } }
        }

        It '带空格的路径应处理' {
            $mockImages = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; FullName = 'C:\Program Files\test1.jpg' }
            )

            $result = Invoke-ParallelUpscale -Images $mockImages -OutputDir 'C:\Program Files\output' -MaxWorkers 1

            $result | Should -Not -BeNullOrEmpty
        }
    }
}
