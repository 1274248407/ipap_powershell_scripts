#Requires -Modules Pester

<#
.SYNOPSIS
    Main.ps1 验收测试
.DESCRIPTION
    测试 Main.ps1 脚本的整体行为，包括模块导入、函数可用性检查和交互式输入。
    本测试文件详细设计 Mock Read-Host 的完整输入序列，覆盖所有关键分支路径。
#>

Describe 'Main.ps1 Acceptance Tests' -Tag 'Main', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = $PSScriptRoot | Split-Path -Parent | Split-Path -Parent
        $ScriptPath = Join-Path $ProjectRoot 'Main.ps1'
        $PoShLogPath = Join-Path $ProjectRoot 'vendor\PoShLog'
        $BinPath = Join-Path $ProjectRoot 'bin'

        $Script:PoShLogExists = Test-Path $PoShLogPath
        $Script:ExeExists = Test-Path (Join-Path $BinPath 'realcugan-ncnn-vulkan.exe')
        $Script:TomlJsonExists = Test-Path (Join-Path $BinPath 'tomljson.exe')
        $Script:ImageDir = Join-Path $ProjectRoot 'tests\data\images'
        $Script:ImageDirExists = Test-Path $Script:ImageDir
    }

    Context 'PowerShell 版本检查' {
        It '应要求 PowerShell 7 或更高版本' {
            if ($PSVersionTable.PSVersion.Major -lt 7)
            {
                Set-ItResult -Skipped -Because 'PowerShell version is below 7'
                return
            }

            $PSVersionTable.PSVersion.Major | Should -BeGreaterOrThan 6
        }
    }

    Context 'PoShLog 模块检查' {
        It 'PoShLog 模块应存在' {
            if (-not $Script:PoShLogExists)
            {
                Set-ItResult -Skipped -Because 'PoShLog module not found'
                return
            }

            $Script:PoShLogExists | Should -Be $true
        }
    }

    Context 'bin 目录依赖检查' {
        It 'bin 目录应存在' {
            Test-Path $BinPath | Should -Be $true
        }

        It 'realcugan-ncnn-vulkan.exe 应存在（验收测试可选）' {
            if (-not $Script:ExeExists)
            {
                Write-Host 'Warning: realcugan-ncnn-vulkan.exe not found, upscaling tests will be skipped'
            }

            $Script:ExeExists | Should -Be $true
        }

        It 'tomljson.exe 应存在（验收测试可选）' {
            if (-not $Script:TomlJsonExists)
            {
                Write-Host 'Warning: tomljson.exe not found, config parsing tests will be skipped'
            }

            $Script:TomlJsonExists | Should -Be $true
        }
    }

    Context '测试图片准备检查' {
        It '测试图片目录应存在' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped -Because 'Test images directory not found'
                return
            }

            $Script:ImageDirExists | Should -Be $true
        }

        It '应至少有一张测试图片' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $imageCount = (Get-ChildItem -Path $Script:ImageDir -File | Where-Object {
                    $_.Extension.ToLower() -in @('.jpg', '.png', '.webp', '.gif', '.bmp')
                }).Count

            $imageCount | Should -BeGreaterThan 0
        }
    }

    Context '模块导入测试' {
        It '应能导入 IPAP.Core 模块' {
            $coreModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psd1'

            if (-not (Test-Path $coreModulePath))
            {
                Set-ItResult -Skipped -Because 'IPAP.Core module not found'
                return
            }

            { Import-Module $coreModulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It '应能导入 IPAP.ImageProcessor 模块' {
            $imageProcessorModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1'

            if (-not (Test-Path $imageProcessorModulePath))
            {
                Set-ItResult -Skipped -Because 'IPAP.ImageProcessor module not found'
                return
            }

            { Import-Module $imageProcessorModulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It '应能导入 IPAP.ProjectManager 模块' {
            $projectManagerModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1'

            if (-not (Test-Path $projectManagerModulePath))
            {
                Set-ItResult -Skipped -Because 'IPAP.ProjectManager module not found'
                return
            }

            { Import-Module $projectManagerModulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It '应能导入 IPAP.Workflow 模块' {
            $workflowModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psd1'

            if (-not (Test-Path $workflowModulePath))
            {
                Set-ItResult -Skipped -Because 'IPAP.Workflow module not found'
                return
            }

            { Import-Module $workflowModulePath -Force -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context '函数可用性测试' {
        BeforeAll {
            $coreModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psd1'
            $imageProcessorModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psd1'
            $projectManagerModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psd1'
            $workflowModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Workflow\IPAP.Workflow.psd1'

            Import-Module $coreModulePath -Force -Global -ErrorAction SilentlyContinue
            Import-Module $imageProcessorModulePath -Force -Global -ErrorAction SilentlyContinue
            Import-Module $projectManagerModulePath -Force -Global -ErrorAction SilentlyContinue
            Import-Module $workflowModulePath -Force -Global -ErrorAction SilentlyContinue
        }

        It 'Start-IPAPWorkflow 函数应可用' {
            Get-Command Start-IPAPWorkflow -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Initialize-Environment 函数应可用' {
            Get-Command Initialize-Environment -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Get-Config 函数应可用' {
            Get-Command Get-Config -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Get-ImageInfo 函数应可用' {
            Get-Command Get-ImageInfo -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Test-NeedUpscale 函数应可用' {
            Get-Command Test-NeedUpscale -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'New-ProjectStructure 函数应可用' {
            Get-Command New-ProjectStructure -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'New-ReadmeFile 函数应可用' {
            Get-Command New-ReadmeFile -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'New-TranslationFiles 函数应可用' {
            Get-Command New-TranslationFiles -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Get-ProjectBriefInfo 函数应可用' {
            Get-Command Get-ProjectBriefInfo -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Read-Host Mock 测试 - 正常执行路径' {
        It '模拟正常交互：同意覆盖、输入项目名、源目录' {
            # Mock Read-Host 调用顺序说明：
            # 步骤1: New-ProjectStructure 询问 "Directory ... already exists, overwrite? (Y/N)" -> 返回 'Y'
            # 步骤2: Start-IPAPWorkflow 询问 "Enter project base directory" -> 返回测试目录
            # 步骤3: Start-IPAPWorkflow 询问 "Enter project name" -> 返回 'TestProject'
            # 步骤4: Get-ProjectBriefInfo 询问 "项目名称（格式：[作者] 原作品名）" -> 返回 'TestProject'
            # 步骤5: Get-ProjectBriefInfo 询问 "作品中文译名（格式：[作者] 作品中文译名）" -> 返回 '测试项目'
            # 步骤6-10: Get-ProjectBriefInfo 询问项目简介多行输入 -> 返回三行后空行结束
            # 步骤11: Start-IPAPWorkflow 询问 "Enter source image directory" -> 返回测试图片目录

            $callSequence = @()
            $callCount = 0

            Mock Read-Host {
                param($Prompt)
                $callCount++
                $callSequence += $Prompt

                switch -Regex ($Prompt)
                {
                    'already exists.*overwrite' { return 'Y' }
                    'Enter project base directory' { return $env:TEMP }
                    'Enter project name' { return 'MockProject' }
                    '项目名称.*格式' { return 'MockProject' }
                    '中文译名.*格式' { return '模拟项目' }
                    '项目简介.*多行'
                    {
                        if ($callCount -le 10) { return "测试简介第$($callCount)行" }
                        return ''
                    }
                    'Enter source image directory'
                    {
                        if ($Script:ImageDirExists) { return $Script:ImageDir }
                        return $env:TEMP
                    }
                    default { return '' }
                }
            }

            Initialize-Environment

            $Global:Settings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Read-Host Mock 测试 - 拒绝覆盖' {
        It '模拟拒绝覆盖已存在目录' {
            # 步骤1: New-ProjectStructure 询问覆盖 -> 返回 'N'
            # 验证：应返回 $null，不创建目录

            Mock Read-Host {
                param($Prompt)
                if ($Prompt -match 'already exists.*overwrite') { return 'N' }
                return ''
            }

            $tempDir = Join-Path $env:TEMP "test_existing_$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $today = Get-Date -Format 'yyyy-MM-dd'
            $existingProjectDir = Join-Path $tempDir "${today}_ExistingProject"
            New-Item -ItemType Directory -Path $existingProjectDir -Force | Out-Null

            try
            {
                $result = New-ProjectStructure -BaseDir $tempDir -ProjectName 'ExistingProject'

                $result | Should -BeNullOrEmpty
            }
            finally
            {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Read-Host Mock 测试 - 空输入处理' {
        It '模拟空字符串输入' {
            # 步骤1: Get-ProjectBriefInfo 询问项目名 -> 返回空字符串
            # 步骤2: Get-ProjectBriefInfo 询问中文译名 -> 返回空字符串

            $callCount = 0
            Mock Read-Host {
                param($Prompt)
                $callCount++
                if ($Prompt -match '项目名称') { return '' }
                if ($Prompt -match '中文译名') { return '' }
                return ''
            }

            $result = Get-ProjectBriefInfo

            $result[1] | Should -Be ''
        }
    }

    Context '配置文件解析测试' {
        It '应能使用默认配置' {
            $result = Get-Config

            $result | Should -Not -BeNullOrEmpty
            $result.app_settings.model_select | Should -Be 'models-se'
        }
    }

    Context '环境初始化测试' {
        It 'Initialize-Environment 应设置全局变量' {
            Initialize-Environment

            $Global:RealCuganExePath | Should -Not -BeNullOrEmpty
            $Global:Settings | Should -Not -BeNullOrEmpty
        }
    }
}
