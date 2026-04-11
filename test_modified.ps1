# Test modified IPAP Workflow PowerShell module

# Import the module
Import-Module -Name '.\ipap_workflow.psm1' -Force

Write-Host '=== Test Started ==='

# Test 1: Module initialization
Write-Host '\nTest 1: Module initialization'
try {
    $result = Initialize-IpapModule
    if ($result) {
        Write-Host '✅ Success'
    }
    else {
        Write-Host '❌ Failed'
    }
}
catch {
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 2: Config loading
Write-Host '\nTest 2: Config loading'
try {
    $config = Get-IpapConfig -ConfigPath '.\config.toml'
    if ($config) {
        Write-Host '✅ Success'
        Write-Host "  Base project dir: $($config.paths.base_project_dir)"
        Write-Host "  Max workers: $($config.app_settings.max_workers)"
    }
    else {
        Write-Host '❌ Failed'
    }
}
catch {
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 3: Project structure creation
Write-Host '\nTest 3: Project structure creation'
try {
    $testDir = 'D:\documents\code\IPAP_workflow\test_output'
    if (-not (Test-Path -Path $testDir -PathType Container)) {
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
    }
    $projDir = New-IpapProjectStructure -BaseDirectory $testDir -ProjectName 'Test'
    if ($projDir) {
        Write-Host "✅ Success: $projDir"
        # Verify directory structure
        $expectedDirs = @(
            '02_Preprocessing\raw_source',
            '03_Translation',
            '04_Typesetting\workfiles'
        )
        foreach ($dir in $expectedDirs) {
            $dirPath = Join-Path -Path $projDir -ChildPath $dir
            if (Test-Path -Path $dirPath -PathType Container) {
                Write-Host "  ✅ Directory exists: $dir"
            }
            else {
                Write-Host "  ❌ Directory missing: $dir"
            }
        }
    }
    else {
        Write-Host '❌ Failed'
    }
}
catch {
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 4: Create test images directory
Write-Host '\nTest 4: Create test images'
try {
    $testImagesDir = 'D:\documents\code\IPAP_workflow\test_images'
    if (-not (Test-Path -Path $testImagesDir -PathType Container)) {
        New-Item -Path $testImagesDir -ItemType Directory -Force | Out-Null
        # Create a simple test image
        Add-Type -AssemblyName System.Drawing
        $image = New-Object System.Drawing.Bitmap(100, 100)
        $graphics = [System.Drawing.Graphics]::FromImage($image)
        $graphics.Clear([System.Drawing.Color]::White)
        $font = New-Object System.Drawing.Font('Arial', 12)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
        $graphics.DrawString('Test Image', $font, $brush, 10, 45)
        $image.Save("$testImagesDir\test1.png", [System.Drawing.Imaging.ImageFormat]::Png)
        $image.Dispose()
        $graphics.Dispose()
        $font.Dispose()
        $brush.Dispose()
        Write-Host '✅ Success: Test image created'
    }
    else {
        Write-Host '✅ Success: Test images directory already exists'
    }
}
catch {
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 5: Image scanning
Write-Host '\nTest 5: Image scanning'
try {
    $testImagesDir = 'D:\documents\code\IPAP_workflow\test_images'
    $imageFiles = Get-IpapImageFiles -DirectoryPath $testImagesDir
    if ($imageFiles.Count -gt 0) {
        Write-Host "✅ Success, found $($imageFiles.Count) images"
        foreach ($imageFile in $imageFiles) {
            Write-Host "  - $($imageFile.Name)"
        }
    }
    else {
        Write-Host '⚠️ No images found'
    }
}
catch {
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Test 6: Image analysis
Write-Host '\nTest 6: Image analysis'
try {
    $testImagesDir = 'D:\documents\code\IPAP_workflow\test_images'
    $imageFiles = Get-IpapImageFiles -DirectoryPath $testImagesDir
    if ($imageFiles.Count -gt 0) {
        $imageInfo = Get-IpapImageInfo -ImageFiles $imageFiles
        Write-Host '✅ Success'
        Write-Host "  Count: $($imageInfo.Count)"
        Write-Host "  Total Size: $([math]::Round($imageInfo.TotalSize / 1KB, 2)) KB"
        Write-Host "  Average Size: $([math]::Round($imageInfo.AvgSize / 1KB, 2)) KB"
    }
    else {
        Write-Host '⚠️ No images to analyze'
    }
}
catch {
    Write-Host "❌ Failed: $($PSItem.Exception.Message)"
}

# Clean up
Write-Host '\nCleaning up test directories...'
try {
    $testDir = 'D:\documents\code\IPAP_workflow\test_output'
    if (Test-Path -Path $testDir -PathType Container) {
        Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host '✅' Test output directory cleaned"
    }
} catch {
    Write-Host "❌ Failed to clean up: $($PSItem.Exception.Message)'
}

Write-Host '\n=== Test Completed ==="
