#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ProjectManager - New-TranslationFiles 单元测试
.DESCRIPTION
    测试 New-TranslationFiles 函数的翻译文件生成逻辑。
#>

Describe 'New-TranslationFiles Unit Tests' -Tag 'New-TranslationFiles', 'IPAP.ProjectManager' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ProjectManager\IPAP.ProjectManager.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }

        Mock -ModuleName IPAP.ProjectManager Write-InfoLog {}
        Mock -ModuleName IPAP.ProjectManager Write-ErrorLog {}
        Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
        Mock -ModuleName IPAP.ProjectManager New-Item {}
        Mock -ModuleName IPAP.ProjectManager Out-File {}
    }

    AfterAll {
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Normal Execution' {
        It '应创建翻译目录' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}

            New-TranslationFiles -ProjectDir 'C:\Projects\Test'

            Should -Invoke -ModuleName IPAP.ProjectManager New-Item -Times 1
        }

        It '应创建 project_brief.md 文件' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-TranslationFiles -ProjectDir 'C:\Projects\Test'

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 2
        }

        It '应创建 glossary.json 文件' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-TranslationFiles -ProjectDir 'C:\Projects\Test'

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 2
        }
    }

    Context 'BriefText 参数测试' {
        It 'BriefText 为 $null 时不应创建 project_brief.md' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-TranslationFiles -ProjectDir 'C:\Projects\Test' -BriefText $null

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 1
        }

        It 'BriefText 有值时应写入 project_brief.md' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-TranslationFiles -ProjectDir 'C:\Projects\Test' -BriefText 'Test brief content'

            Should -Invoke -ModuleName IPAP.ProjectManager Out-File -Times 2
        }
    }

    Context '目录已存在测试' {
        It '翻译目录已存在时应跳过创建' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $true }
            Mock -ModuleName IPAP.ProjectManager Out-File {}

            New-TranslationFiles -ProjectDir 'C:\Projects\Test'

            Should -Invoke -ModuleName IPAP.ProjectManager New-Item -Times 0
        }
    }

    Context '必填参数测试' {
        It 'ProjectDir 缺失时应报错' {
            { New-TranslationFiles } | Should -Throw
        }
    }

    Context '错误处理测试' {
        It 'New-Item 失败时应记录错误' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item { throw 'Access denied' }

            New-TranslationFiles -ProjectDir 'C:\Projects\Test'

            Should -Invoke -ModuleName IPAP.ProjectManager Write-ErrorLog -Times 1
        }

        It 'Out-File 失败时应记录错误' {
            Mock -ModuleName IPAP.ProjectManager Test-Path { return $false }
            Mock -ModuleName IPAP.ProjectManager New-Item {}
            Mock -ModuleName IPAP.ProjectManager Out-File { throw 'Write error' }

            New-TranslationFiles -ProjectDir 'C:\Projects\Test'

            Should -Invoke -ModuleName IPAP.ProjectManager Write-ErrorLog -Times 1
        }
    }
}
