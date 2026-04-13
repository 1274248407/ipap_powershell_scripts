# 测试 IPAP Workflow PowerShell 模块的所有功能

# 导入模块
Import-Module -Name '.\ipap_workflow.psm1' -Force

# 测试配置
$testConfigPath = '.\config.toml'
$testBaseDir = 'D:\documents\code\IPAP_workflow\test_output'
$testProjectName = '测试项目'
$testSourceDir = 'D:\documents\code\IPAP_workflow\test_images'

# 创建测试目录
if (-not (Test-Path -Path $testBaseDir -PathType Container))
{
    New-Item -Path $testBaseDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -Path $testSourceDir -PathType Container))
{
    New-Item -Path $testSourceDir -ItemType Directory -Force | Out-Null
    # 创建测试图片文件
    for ($i = 1; $i -le 3; $i++)
    {
        $testImagePath = Join-Path -Path $testSourceDir -ChildPath "test$i.png"
        # 创建一个简单的测试图片
        Add-Type -AssemblyName System.Drawing
        $image = New-Object System.Drawing.Bitmap(100, 100)
        $graphics = [System.Drawing.Graphics]::FromImage($image)
        $graphics.Clear([System.Drawing.Color]::White)
        $font = New-Object System.Drawing.Font('Arial', 12)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
        $graphics.DrawString("Test Image $i", $font, $brush, 10, 45)
        $image.Save($testImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
        $image.Dispose()
        $graphics.Dispose()
        $font.Dispose()
        $brush.Dispose()
    }
}

# 测试函数
function Test-ProjectStructureCreation
{
    <#
    .SYNOPSIS
        测试项目目录结构创建功能。

    .DESCRIPTION
        测试 New-IpapProjectStructure 函数是否能够正确创建项目目录结构。
        验证创建的目录结构是否符合预期。

    .EXAMPLE
        Test-ProjectStructureCreation

    .EXAMPLE
        # 通过管道调用
        $true | Test-ProjectStructureCreation

    .INPUTS
        无

    .OUTPUTS
        System.Boolean

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()
    
    Write-Host '\n=== 测试 1: 项目目录结构创建 ===' -ForegroundColor Cyan
    
    try
    {
        $projDir = New-IpapProjectStructure -BaseDirectory $testBaseDir -ProjectName $testProjectName
        Write-Host "✅ 项目目录结构创建成功: $projDir" -ForegroundColor Green
        
        # 验证目录结构
        $expectedDirs = @(
            '02_Preprocessing\raw_source',
            '02_Preprocessing\original_non_text_raw',
            '02_Preprocessing\inpainted',
            '02_Preprocessing\mask',
            '03_Translation',
            '04_Typesetting\workfiles',
            '04_Typesetting\final_pages'
        )
        
        $allDirsExist = $true
        foreach ($dir in $expectedDirs)
        {
            $dirPath = Join-Path -Path $projDir -ChildPath $dir
            if (Test-Path -Path $dirPath -PathType Container)
            {
                Write-Host "  ✅ 目录存在: $dir" -ForegroundColor Green
            }
            else
            {
                Write-Host "  ❌ 目录不存在: $dir" -ForegroundColor Red
                $allDirsExist = $false
            }
        }
        
        return $allDirsExist
    }
    catch
    {
        Write-Host "❌ 项目目录结构创建失败: $($PSItem.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-ConfigLoading
{
    <#
    .SYNOPSIS
        测试配置文件加载功能。

    .DESCRIPTION
        测试 Get-IpapConfig 函数是否能够正确加载配置文件。
        验证加载的配置是否包含预期的设置。

    .EXAMPLE
        Test-ConfigLoading

    .EXAMPLE
        # 通过管道调用
        $true | Test-ConfigLoading

    .INPUTS
        无

    .OUTPUTS
        System.Boolean

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()
    
    Write-Host '\n=== 测试 2: 配置文件加载 ===' -ForegroundColor Cyan
    
    try
    {
        $config = Get-IpapConfig -ConfigPath $testConfigPath
        if ($config)
        {
            Write-Host '✅ 配置文件加载成功' -ForegroundColor Green
            Write-Host "  基础项目目录: $($config.paths.base_project_dir)" -ForegroundColor Gray
            Write-Host "  最大工作线程: $($config.app_settings.max_workers)" -ForegroundColor Gray
            Write-Host "  高清化模型: $($config.app_settings.model_select)" -ForegroundColor Gray
            return $true
        }
        else
        {
            Write-Host '❌ 配置文件加载失败' -ForegroundColor Red
            return $false
        }
    }
    catch
    {
        Write-Host "❌ 配置文件加载异常: $($PSItem.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-ImageScanning
{
    <#
    .SYNOPSIS
        测试图片文件扫描功能。

    .DESCRIPTION
        测试 Get-IpapImageFiles 函数是否能够正确扫描目录中的图片文件。
        验证扫描结果是否包含预期的图片文件。

    .EXAMPLE
        Test-ImageScanning

    .EXAMPLE
        # 通过管道调用
        $true | Test-ImageScanning

    .INPUTS
        无

    .OUTPUTS
        System.Boolean

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()
    
    Write-Host '\n=== 测试 3: 图片文件扫描 ===' -ForegroundColor Cyan
    
    try
    {
        $imageFiles = Get-IpapImageFiles -DirectoryPath $testSourceDir
        Write-Host "✅ 图片文件扫描完成，找到 $($imageFiles.Count) 张图片" -ForegroundColor Green
        foreach ($imageFile in $imageFiles)
        {
            Write-Host "  - $($imageFile.Name)" -ForegroundColor Gray
        }
        return $imageFiles.Count -gt 0
    }
    catch
    {
        Write-Host "❌ 图片文件扫描失败: $($PSItem.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-ImageAnalysis
{
    <#
    .SYNOPSIS
        测试图片分析功能。

    .DESCRIPTION
        测试 Get-IpapImageInfo 函数是否能够正确分析图片文件的属性。
        验证分析结果是否包含预期的信息。

    .EXAMPLE
        Test-ImageAnalysis

    .EXAMPLE
        # 通过管道调用
        $true | Test-ImageAnalysis

    .INPUTS
        无

    .OUTPUTS
        System.Boolean

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()
    
    Write-Host '\n=== 测试 4: 图片分析 ===' -ForegroundColor Cyan
    
    try
    {
        $imageFiles = Get-IpapImageFiles -DirectoryPath $testSourceDir
        $imageInfo = Get-IpapImageInfo -ImageFiles $imageFiles
        Write-Host '✅ 图片分析完成' -ForegroundColor Green
        Write-Host "  图片数量: $($imageInfo.Count)" -ForegroundColor Gray
        Write-Host "  总大小: $([math]::Round($imageInfo.TotalSize / 1KB, 2)) KB" -ForegroundColor Gray
        Write-Host "  平均大小: $([math]::Round($imageInfo.AvgSize / 1KB, 2)) KB" -ForegroundColor Gray
        return $true
    }
    catch
    {
        Write-Host "❌ 图片分析失败: $($PSItem.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-ImageCopyAndAnalyze
{
    <#
    .SYNOPSIS
        测试图片复制和分析功能。

    .DESCRIPTION
        测试 Copy-IpapImagesAndAnalyze 函数是否能够正确复制图片文件并分析其属性。
        验证复制和分析结果是否符合预期。

    .EXAMPLE
        Test-ImageCopyAndAnalyze

    .EXAMPLE
        # 通过管道调用
        $true | Test-ImageCopyAndAnalyze

    .INPUTS
        无

    .OUTPUTS
        System.Boolean

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()
    
    Write-Host '\n=== 测试 5: 图片复制和分析 ===' -ForegroundColor Cyan
    
    try
    {
        $projDir = New-IpapProjectStructure -BaseDirectory $testBaseDir -ProjectName 'test_copy'
        $imageFiles, $imageCount, $totalSize, $maxSize = Copy-IpapImagesAndAnalyze -SourcePath $testSourceDir -ProjectDirectory $projDir
        Write-Host '✅ 图片复制和分析完成' -ForegroundColor Green
        Write-Host "  复制的图片数量: $imageCount" -ForegroundColor Gray
        Write-Host "  总大小: $([math]::Round($totalSize / 1KB, 2)) KB" -ForegroundColor Gray
        Write-Host "  最大大小: $([math]::Round($maxSize / 1KB, 2)) KB" -ForegroundColor Gray
        return $imageCount -gt 0
    }
    catch
    {
        Write-Host "❌ 图片复制和分析失败: $($PSItem.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-ProjectFilesCreation
{
    <#
    .SYNOPSIS
        测试项目文件创建功能。

    .DESCRIPTION
        测试 New-IpapProjectFiles 函数是否能够正确创建项目相关文件。
        验证创建的文件是否符合预期。

    .EXAMPLE
        Test-ProjectFilesCreation

    .EXAMPLE
        # 通过管道调用
        $true | Test-ProjectFilesCreation

    .INPUTS
        无

    .OUTPUTS
        System.Boolean

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()
    
    Write-Host '\n=== 测试 6: 项目文件创建 ===' -ForegroundColor Cyan
    
    try
    {
        $projDir = New-IpapProjectStructure -BaseDirectory $testBaseDir -ProjectName 'test_files'
        New-IpapProjectFiles -ProjectDirectory $projDir -BriefText '测试项目简介' -ProjectName '测试项目' -ImageCount 5 -AverageSizeKB 500
        
        # 验证文件创建
        $readmePath = Join-Path -Path $projDir -ChildPath 'README.md'
        $briefPath = Join-Path -Path $projDir -ChildPath '03_Translation\project_brief.md'
        $glossaryPath = Join-Path -Path $projDir -ChildPath '03_Translation\glossary.json'
        
        $allFilesExist = $true
        if (Test-Path -Path $readmePath -PathType Leaf)
        {
            Write-Host '  ✅ README.md 文件存在' -ForegroundColor Green
        }
        else
        {
            Write-Host '  ❌ README.md 文件不存在' -ForegroundColor Red
            $allFilesExist = $false
        }
        
        if (Test-Path -Path $briefPath -PathType Leaf)
        {
            Write-Host '  ✅ project_brief.md 文件存在' -ForegroundColor Green
        }
        else
        {
            Write-Host '  ❌ project_brief.md 文件不存在' -ForegroundColor Red
            $allFilesExist = $false
        }
        
        if (Test-Path -Path $glossaryPath -PathType Leaf)
        {
            Write-Host '  ✅ glossary.json 文件存在' -ForegroundColor Green
        }
        else
        {
            Write-Host '  ❌ glossary.json 文件不存在' -ForegroundColor Red
            $allFilesExist = $false
        }
        
        return $allFilesExist
    }
    catch
    {
        Write-Host "❌ 项目文件创建失败: $($PSItem.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# 运行所有测试
$testResults = @()
$testResults += Test-ProjectStructureCreation
$testResults += Test-ConfigLoading
$testResults += Test-ImageScanning
$testResults += Test-ImageAnalysis
$testResults += Test-ImageCopyAndAnalyze
$testResults += Test-ProjectFilesCreation

# 汇总测试结果
Write-Host '\n=== 测试结果汇总 ===' -ForegroundColor Cyan
$passedTests = ($testResults | Where-Object { $PSItem -eq $true }).Count
$totalTests = $testResults.Count

Write-Host "通过测试: $passedTests/$totalTests" -ForegroundColor Green

if ($passedTests -eq $totalTests)
{
    Write-Host '✅ 所有测试通过！PowerShell 模块功能正常。' -ForegroundColor Green
}
else
{
    Write-Host '❌ 部分测试失败，需要检查。' -ForegroundColor Red
}

# 清理测试目录
Write-Host '\n清理测试目录...' -ForegroundColor Yellow
if (Test-Path -Path $testBaseDir -PathType Container)
{
    Remove-Item -Path $testBaseDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '✅ 测试目录已清理' -ForegroundColor Green
}

Write-Host '\n测试完成！' -ForegroundColor Cyan