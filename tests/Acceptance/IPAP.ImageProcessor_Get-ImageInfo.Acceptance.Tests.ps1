#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP.ImageProcessor - Get-ImageInfo 验收测试
.DESCRIPTION
    验收测试 Get-ImageInfo 函数在真实环境中的图片目录分析能力。
    测试图片准备清单：
    - 正常图片：test_image_1.jpg, test_image_2.png, test_image_3.webp
    - 边界图片：tinyimg.jpg, image (1).jpg, long_filename_image_...
    - 异常图片：corrupted_image.jpg, fake_image.jpg, empty_image.jpg
    - 非图片文件：not_an_image.txt
#>

Describe 'Get-ImageInfo Acceptance Tests' -Tag 'Get-ImageInfo', 'IPAP.ImageProcessor', 'Acceptance' {
    BeforeAll {
        $ProjectRoot = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
        $ModulePath = Join-Path $ProjectRoot 'Modules\IPAP.ImageProcessor\IPAP.ImageProcessor.psm1'
        $ImageDir = Join-Path $ProjectRoot 'tests\data\images'

        if (Test-Path $ModulePath)
        {
            Import-Module $ModulePath -Force -Global
        }
        else
        {
            Write-Host "IPAP.ImageProcessor module not found at: $ModulePath" -ForegroundColor Red
        }

        $Script:ImageDirExists = Test-Path $ImageDir
        $Script:TestImages = @(
            'test_image_1.jpg',
            'test_image_2.png',
            'test_image_3.webp',
            'tinyimg.jpg',
            'image (1).jpg'
        )
    }

    AfterAll {
        Remove-Module 'IPAP.ImageProcessor' -ErrorAction SilentlyContinue
    }

    Context '正常执行路径 - Real Image Directory' {
        It '应能分析 tests/data/images 目录' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped -Because "Image directory not found: $ImageDir"
                return
            }

            $result = Get-ImageInfo -SourceDir $ImageDir

            $result | Should -Not -BeNullOrEmpty
            $result.Images | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }

        It '应正确统计图片数量' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Get-ImageInfo -SourceDir $ImageDir

            $result.Count | Should -BeGreaterOrThan 1
        }

        It '应正确计算总大小' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Get-ImageInfo -SourceDir $ImageDir

            $result.TotalSize | Should -BeGreaterThan 0
        }

        It '应正确计算平均大小' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Get-ImageInfo -SourceDir $ImageDir

            if ($result.Count -gt 0)
            {
                $result.AverageSize | Should -BeGreaterThan 0
            }
        }
    }

    Context '图片格式验证' {
        It '应只包含支持的图片格式' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $result = Get-ImageInfo -SourceDir $ImageDir

            foreach ($image in $result.Images)
            {
                $image.Extension.ToLower() | Should -BeIn @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')
            }
        }

        It '应正确过滤非图片文件' {
            if (-not $Script:ImageDirExists)
            {
                Set-ItResult -Skipped
                return
            }

            $beforeCount = (Get-ChildItem -Path $ImageDir -File).Count
            $result = Get-ImageInfo -SourceDir $ImageDir

            $result.Count | Should -BeLessThan $beforeCount
        }
    }

    Context '目录不存在测试' {
        It '不存在的目录应返回空结果' {
            $nonExistentDir = Join-Path $env:TEMP "non_existent_dir_$(Get-Random)"

            $result = Get-ImageInfo -SourceDir $nonExistentDir

            $result.Images | Should -BeEmpty
            $result.Count | Should -Be 0
            $result.TotalSize | Should -Be 0
        }
    }
}
