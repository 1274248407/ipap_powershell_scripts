#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ProjectManager - New-TranslationFiles 验收测试
.DESCRIPTION
    验收测试 New-TranslationFiles 函数在真实环境中的翻译文件生成能力。
#>

Describe 'New-TranslationFiles Acceptance Tests' -Tag 'New-TranslationFiles', 'IPAP.ProjectManager', 'Acceptance' {
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

        $Script:TestProjectDir = Join-Path $env:TEMP "ipap_translation_test_$( Get-Random)"
    }

    AfterAll {
        if (Test-Path $Script:TestProjectDir)
        {
            Remove-Item -Path $Script:TestProjectDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常文件生成' {
        It '应成功创建 03_Translation 目录' {
            New-TranslationFiles -ProjectDir $Script:TestProjectDir

            $translationDir = Join-Path $Script:TestProjectDir '03_Translation'
            Test-Path $translationDir | Should -Be $true
        }

        It '应创建 project_brief.md 文件' {
            New-TranslationFiles -ProjectDir $Script:TestProjectDir -BriefText 'Test brief'

            $briefFile = Join-Path $Script:TestProjectDir '03_Translation\project_brief.md'
            Test-Path $briefFile | Should -Be $true
        }

        It '应创建 glossary.json 文件' {
            New-TranslationFiles -ProjectDir $Script:TestProjectDir

            $glossaryFile = Join-Path $Script:TestProjectDir '03_Translation\glossary.json'
            Test-Path $glossaryFile | Should -Be $true
        }
    }

    Context '文件内容测试' {
        It 'glossary.json 应为有效 JSON' {
            New-TranslationFiles -ProjectDir $Script:TestProjectDir

            $glossaryFile = Join-Path $Script:TestProjectDir '03_Translation\glossary.json'
            $content = Get-Content $glossaryFile -Raw

            { $content | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'BriefText 应写入 project_brief.md' {
            New-TranslationFiles -ProjectDir $Script:TestProjectDir -BriefText 'This is a test brief'

            $briefFile = Join-Path $Script:TestProjectDir '03_Translation\project_brief.md'
            $content = Get-Content $briefFile -Raw

            $content | Should -Match 'This is a test brief'
        }
    }

    Context '目录已存在场景' {
        It '目录已存在时应直接创建文件' {
            New-TranslationFiles -ProjectDir $Script:TestProjectDir
            New-TranslationFiles -ProjectDir $Script:TestProjectDir

            $briefFile = Join-Path $Script:TestProjectDir '03_Translation\project_brief.md'
            $glossaryFile = Join-Path $Script:TestProjectDir '03_Translation\glossary.json'

            Test-Path $briefFile | Should -Be $true
            Test-Path $glossaryFile | Should -Be $true
        }
    }
}
