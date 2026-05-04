#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ProjectManager - New-ProjectStructure 验收测试
.DESCRIPTION
    验收测试 New-ProjectStructure 函数在真实环境中的目录创建能力。
#>

Describe 'New-ProjectStructure Acceptance Tests' -Tag 'New-ProjectStructure', 'IPAP.ProjectManager', 'Acceptance' {
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

        $Script:TestBaseDir = Join-Path $env:TEMP "ipap_project_test_$(Get-Random)"
    }

    AfterAll {
        if (Test-Path $Script:TestBaseDir)
        {
            Remove-Item -Path $Script:TestBaseDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Module 'IPAP.ProjectManager' -ErrorAction SilentlyContinue
    }

    Context '正常目录创建' {
        It '应成功创建项目目录结构' {
            New-Item -ItemType Directory -Path $Script:TestBaseDir -Force | Out-Null

            $result = New-ProjectStructure -BaseDir $Script:TestBaseDir -ProjectName 'TestProject'

            $result | Should -Not -BeNullOrEmpty
            Test-Path $result | Should -Be $true
        }

        It '应创建所有子目录' {
            New-Item -ItemType Directory -Path $Script:TestBaseDir -Force | Out-Null

            $result = New-ProjectStructure -BaseDir $Script:TestBaseDir -ProjectName 'TestProject'

            $expectedSubDirs = @(
                'raw_source',
                'original_non_text_raw',
                'inpainted',
                'mask',
                '03_Translation',
                'workfiles',
                'final_pages'
            )

            foreach ($subDir in $expectedSubDirs)
            {
                $fullPath = Join-Path $result "02_Preprocessing\$subDir"
                if ($subDir -match '^0[34]')
                {
                    $fullPath = Join-Path $result $subDir
                }
                if ($subDir -eq 'workfiles' -or $subDir -eq 'final_pages')
                {
                    $fullPath = Join-Path $result "04_Typesetting\$subDir"
                }
                Test-Path $fullPath | Should -Be $true
            }
        }

        It '目录名应包含日期前缀' {
            New-Item -ItemType Directory -Path $Script:TestBaseDir -Force | Out-Null

            $result = New-ProjectStructure -BaseDir $Script:TestBaseDir -ProjectName 'MyProject'

            $today = Get-Date -Format 'yyyy-MM-dd'
            $result | Should -Match $today
        }
    }

    Context '目录已存在场景' {
        It '目录已存在时返回 $null（用户拒绝覆盖）' {
            New-Item -ItemType Directory -Path $Script:TestBaseDir -Force | Out-Null
            $existingDir = Join-Path $Script:TestBaseDir "$(Get-Date -Format 'yyyy-MM-dd')_ExistingProject"
            New-Item -ItemType Directory -Path $existingDir -Force | Out-Null

            Mock Read-Host { return 'N' }

            $result = New-ProjectStructure -BaseDir $Script:TestBaseDir -ProjectName 'ExistingProject'

            $result | Should -BeNullOrEmpty
        }
    }
}
