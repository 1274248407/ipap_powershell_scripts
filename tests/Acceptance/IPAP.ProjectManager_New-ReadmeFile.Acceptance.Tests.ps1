#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ProjectManager - New-ReadmeFile 验收测试
.DESCRIPTION
    验收测试 New-ReadmeFile 函数在真实环境中的 README 文件生成能力。
#>

Describe 'New-ReadmeFile Acceptance Tests' -Tag 'New-ReadmeFile', 'IPAP.ProjectManager', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.ProjectManager module not found at: $ModulePath" -ForegroundColor Red
        }

        $Script:TestProjectDir = Join-Path $env:TEMP "ipap_readme_test_$(Get-Random)"
        New-Item -ItemType Directory -Path $Script:TestProjectDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $Script:TestProjectDir)
        {
            Remove-Item -Path $Script:TestProjectDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常文件生成' {
        It '应成功创建 README.md 文件' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'TestProject' -ImageCount 50 -NeedUpscale $true -UpscaleRatio 2

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            Test-Path $readmePath | Should -Be $true
        }

        It 'README.md 应包含项目名称' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'MyTestProject' -ImageCount 30 -NeedUpscale $false

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            $content | Should -Match 'MyTestProject'
        }

        It 'README.md 应包含图片数量' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'Test' -ImageCount 100 -NeedUpscale $false

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            $content | Should -Match '100'
        }
    }

    Context 'Upscale 状态测试' {
        It 'NeedUpscale 为 $true 时应有 X 标记' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'Test' -ImageCount 50 -NeedUpscale $true

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            $content | Should -Match '\[X\]'
        }

        It 'NeedUpscale 为 $false 时应有空格标记' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'Test' -ImageCount 50 -NeedUpscale $false

            $readmePath = Join-Path $Script:TestProjectDir 'README.md'
            $content = Get-Content $readmePath -Raw
            $content | Should -Match '\[\s\]'
        }
    }

    Context '覆盖已有文件' {
        It '文件已存在时应覆盖' {
            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'First' -ImageCount 10 -NeedUpscale $false
            $firstContent = Get-Content (Join-Path $Script:TestProjectDir 'README.md') -Raw

            New-ReadmeFile -ProjectDir $Script:TestProjectDir -ProjectName 'Second' -ImageCount 20 -NeedUpscale $true
            $secondContent = Get-Content (Join-Path $Script:TestProjectDir 'README.md') -Raw

            $secondContent | Should -Match 'Second'
            $secondContent | Should -Not -Match 'First'
        }
    }
}
