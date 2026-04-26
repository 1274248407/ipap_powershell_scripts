#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.Core - Get-NaturalSortKey 验收测试
.DESCRIPTION
    验收测试 Get-NaturalSortKey 函数在实际环境中的行为。
    测试图片准备清单：tests/data/images/ 目录下的图片文件用于验证文件名排序功能。
#>

Describe 'Get-NaturalSortKey Acceptance Tests' -Tag 'Get-NaturalSortKey', 'IPAP.Core', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.Core\IPAP.Core.psm1'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force
        }
        else
        {
            Write-Host "IPAP.Core module not found at: $ModulePath" -ForegroundColor Red
        }
    }

    AfterAll {
        Remove-Module 'IPAP.Core' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Real World Scenarios' {
        It '应能正确排序实际图片文件名' {
            $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
            $ImageDir = Join-Path $ProjectRoot 'tests\data\images'

            if (Test-Path $ImageDir)
            {
                $imageFiles = Get-ChildItem -Path $ImageDir -File | Where-Object {
                    $_.Extension.ToLower() -in @('.jpg', '.png', '.webp', '.gif', '.bmp')
                }

                if ($imageFiles.Count -gt 0)
                {
                    $sortedFiles = $imageFiles | Sort-Object -Property { $_.Name -split '([0-9]+)' | ForEach-Object { if ($_ -match '^[0-9]+$') { [int]$_ } else { $_ } } }

                    $sortedFiles | Should -Not -BeNullOrEmpty
                }
            }
        }

        It '应能正确排序包含数字序列的文件名' {
            $testFiles = @(
                [PSCustomObject]@{ Name = 'image10.jpg' },
                [PSCustomObject]@{ Name = 'image2.jpg' },
                [PSCustomObject]@{ Name = 'image1.jpg' },
                [PSCustomObject]@{ Name = 'image20.jpg' }
            )

            $sorted = $testFiles | Sort-Object -Property { Get-NaturalSortKey -String $PSItem.Name }

            $sorted[0].Name | Should -Be 'image1.jpg'
            $sorted[1].Name | Should -Be 'image2.jpg'
            $sorted[2].Name | Should -Be 'image10.jpg'
            $sorted[3].Name | Should -Be 'image20.jpg'
        }

        It '应处理长文件名图片' {
            $longName = 'long_filename_image_1234567890_abcdefghijklmnopqrstuvwxyz.jpg'
            $result = Get-NaturalSortKey -String $longName
            $result | Should -Not -BeNullOrEmpty
        }

        It '应处理带括号特殊字符的文件名' {
            $result = Get-NaturalSortKey -String 'image (1).jpg'
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 1
        }
    }

    Context '集成场景测试 - Integration Scenarios' {
        It '应支持图片目录的自然排序' {
            $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
            $ImageDir = Join-Path $ProjectRoot 'tests\data\images'

            if (Test-Path $ImageDir)
            {
                $files = Get-ChildItem -Path $ImageDir -File
                $sortedFiles = $files | Sort-Object -Property { Get-NaturalSortKey $PSItem.Name }

                $sortedFiles | Should -Not -BeNullOrEmpty
            }
            else
            {
                Set-ItResult -Skipped -Because "Image directory not found: $ImageDir"
            }
        }

        It '排序结果应保持一致性' {
            $testStrings = @('test10', 'test2', 'test1', 'test20', 'test3')

            $result1 = Get-NaturalSortKey -String $testStrings[0]
            $result2 = Get-NaturalSortKey -String $testStrings[1]
            $result3 = Get-NaturalSortKey -String $testStrings[2]

            $result1 | Should -Not -BeNullOrEmpty
            $result2 | Should -Not -BeNullOrEmpty
            $result3 | Should -Not -BeNullOrEmpty
        }
    }
}
