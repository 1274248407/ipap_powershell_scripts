# Test script for IPAP Workflow PowerShell module
Import-Module -Name '.\ipap_workflow.psm1' -Force

# Test configuration
$testBaseDir = 'D:\documents\code\IPAP_workflow\test_output'
$testProjectName = 'Test Project'
$testSourceDir = 'D:\documents\code\IPAP_workflow\test_images'

# Create test directories
if (-not (Test-Path -Path $testBaseDir -PathType Container))
{
    New-Item -Path $testBaseDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -Path $testSourceDir -PathType Container))
{
    New-Item -Path $testSourceDir -ItemType Directory -Force | Out-Null
    # Create test image files
    for ($i = 1; $i -le 3; $i++)
    {
        $testImagePath = Join-Path -Path $testSourceDir -ChildPath "test$i.png"
        # Create a simple test image
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

Write-Host '=== Test Started ==='

# Test 1: Project structure creation
Write-Host '\nTest 1: Project structure creation'
try
{
    $projDir = New-IpapProjectStructure -BaseDirectory $testBaseDir -ProjectName $testProjectName
    Write-Host "✅ Success: $projDir"
}
catch
{
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 2: Config file loading
Write-Host '\nTest 2: Config file loading'
try
{
    $config = Get-IpapConfig -ConfigPath '.\config.toml'
    if ($config)
    {
        Write-Host '✅ Success'
    }
    else
    {
        Write-Host '❌ Failed'
    }
}
catch
{
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 3: Image scanning
Write-Host '\nTest 3: Image scanning'
try
{
    $imageFiles = Get-IpapImageFiles -DirectoryPath $testSourceDir
    Write-Host "✅ Success, found $($imageFiles.Count) images"
}
catch
{
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 4: Image analysis
Write-Host '\nTest 4: Image analysis'
try
{
    $imageFiles = Get-IpapImageFiles -DirectoryPath $testSourceDir
    $imageInfo = Get-IpapImageInfo -ImageFiles $imageFiles
    Write-Host '✅ Success'
    Write-Host "  Count: $($imageInfo.Count)"
    Write-Host "  Total Size: $([math]::Round($imageInfo.TotalSize / 1KB, 2)) KB"
}
catch
{
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 5: Image copy and analysis
Write-Host '\nTest 5: Image copy and analysis'
try
{
    $projDir = New-IpapProjectStructure -BaseDirectory $testBaseDir -ProjectName 'test_copy'
    $imageFiles, $imageCount, $totalSize, $maxSize = Copy-IpapImagesAndAnalyze -SourcePath $testSourceDir -ProjectDirectory $projDir
    Write-Host "✅ Success, copied $imageCount images"
}
catch
{
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 6: Project files creation
Write-Host '\nTest 6: Project files creation'
try
{
    $projDir = New-IpapProjectStructure -BaseDirectory $testBaseDir -ProjectName 'test_files'
    New-IpapProjectFiles -ProjectDirectory $projDir -BriefText 'Test project brief' -ProjectName 'Test Project' -ImageCount 5 -AverageSizeKB 500
    Write-Host '✅ Success'
}
catch
{
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Clean up test directory
Write-Host '\nCleaning up test directory...'
if (Test-Path -Path $testBaseDir -PathType Container)
{
    Remove-Item -Path $testBaseDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "✅ Test directory cleaned"
}

Write-Host "\n=== Test Completed ==="
