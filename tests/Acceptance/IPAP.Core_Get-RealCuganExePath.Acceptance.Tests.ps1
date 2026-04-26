#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Core - Get-RealCuganExePath 验收测试
.DESCRIPTION
    验收测试 Get-RealCuganExePath 函数在真实环境中的搜索能力。
#>

Describe 'Get-RealCuganExePath Acceptance Tests' -Tag 'Get-RealCuganExePath', 'IPAP.Core', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'
        $BinPath = Join-Path $ProjectRoot 'bin'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.Core module not found at: $ModulePath" -ForegroundColor Red
        }

        $Script:ExeExists = Test-Path (Join-Path $BinPath 'realcugan-ncnn-vulkan.exe')
    }

    AfterAll {
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Real Environment' {
        It '如果 bin 目录存在应能找到 exe' {
            if (-not (Test-Path $BinPath))
            {
                Set-ItResult -Skipped -Because "bin directory not found: $BinPath"
                return
            }

            if (-not $Script:ExeExists)
            {
                Set-ItResult -Skipped -Because 'realcugan-ncnn-vulkan.exe not found in bin directory'
                return
            }

            $result = Get-RealCuganExePath -SearchPath $BinPath

            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match 'realcugan-ncnn-vulkan\.exe$'
            Test-Path $result | Should -Be $true
        }

        It '返回路径应指向存在的文件' {
            if (-not $Script:ExeExists)
            {
                Set-ItResult -Skipped -Because 'exe not found'
                return
            }

            $result = Get-RealCuganExePath -SearchPath $BinPath

            if ($result)
            {
                Test-Path $result | Should -Be $true
            }
        }
    }

    Context '搜索路径边界测试' {
        It '空目录应返回 $null' {
            $emptyDir = Join-Path $env:TEMP "empty_dir_$(Get-Random)"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            try
            {
                $result = Get-RealCuganExePath -SearchPath $emptyDir

                $result | Should -BeNullOrEmpty
            }
            finally
            {
                Remove-Item -Path $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It '不存在的路径应返回 $null' {
            $nonExistent = Join-Path $env:TEMP "non_existent_$(Get-Random)"

            $result = Get-RealCuganExePath -SearchPath $nonExistent

            $result | Should -BeNullOrEmpty
        }
    }
}
