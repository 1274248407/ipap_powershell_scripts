# IPAP Workflow PowerShell 模块

## 模块概述

IPAP Workflow PowerShell 模块是一个专业的图像处理与自动化工作流工具，主要用于漫画本地化处理。它提供了一套完整的工作流程，包括项目目录结构创建、图像高清化、WebP 无损转换、文件归档、项目文档生成等功能，帮助开发者和本地化团队高效处理漫画图像。

该模块是基于 Python 版本的 IPAP Workflow 项目平移而来，保持了与 Python 版本相同的核心功能和业务逻辑，同时利用 PowerShell 7 的特性提供更好的用户体验和性能。

## 模块结构

```
powershell/
├── ipap_workflow.psd1    # 模块清单文件
├── ipap_workflow.psm1    # 主逻辑脚本模块
├── realcugan-ncnn-vulkan-20220728-windows/  # RealCUGAN 工具目录
│   ├── realcugan-ncnn-vulkan.exe
│   └── models-se/        # 模型目录
└── README_PS.md           # 模块文档
```

## 依赖项

- **PowerShell 7** 或更高版本
- **PowerShell-TOML** 模块（用于解析配置文件，版本 1.0.0 或更高）
- **realcugan-ncnn-vulkan** 工具（用于图像高清化，版本 20220728 或更高）
- **cwebp.exe**（可选，用于 WebP 转换，如未提供则使用 .NET 方法）

## 安装方法

### 1. 安装 PowerShell 7

请从官方网站下载并安装 PowerShell 7：
- [PowerShell 7 下载](https://github.com/PowerShell/PowerShell/releases)

### 2. 安装 PowerShell-TOML 模块

模块会在首次运行时自动检测并安装 PowerShell-TOML 模块。也可以手动安装：

```powershell
Install-Module -Name PowerShell-TOML -Scope CurrentUser -Force
```

### 3. 导入 IPAP Workflow 模块

```powershell
# 方法 1：使用绝对路径导入
Import-Module -Name "D:\documents\code\IPAP_workflow\powershell\ipap_workflow.psd1"

# 方法 2：将模块目录添加到 PSModulePath，然后导入
$env:PSModulePath += ";D:\documents\code\IPAP_workflow\powershell"
Import-Module -Name ipap_workflow
```

## 配置文件

模块使用 `config.toml` 文件进行配置，位于项目根目录。主要配置项如下：

### 路径配置

```toml
[paths]
# 漫画/翻译项目工作区的基准目录
base_project_dir = "D:/documents/translation/01_Projects_Active"
# 默认的项目目录名称前缀
project_dir_prefix = ""
# 原始文件归档目录
archive_dir = "D:/documents/translation/02_Archive"
```

### 应用设置

```toml
[app_settings]
# 并行处理高清化任务的最大进程数
max_workers = 8
# 高清化超时时间（秒）
upscale_timeout_sec = 3600
# 模型选择，可选"models-se"或"models-pro"
model_select = "models-se"
```

### 高清化配置

```toml
[upscale]
# 放大倍数，可选值：2, 3, 4
upscale_ratio = 2
# 降噪级别，可选值：0, 1, 2, 3
noise_level = 0
```

### WebP 配置

```toml
[webp]
# 是否启用 WebP 转换
enabled = true
# 是否使用无损压缩
lossless = true
# 压缩质量 (0-100)，仅在非无损模式下有效
quality = 100
```

## 主要函数

### Invoke-IpapCompleteWorkflow

执行完整的工作流，包括项目设置、图片处理、文档创建等。

**参数**：
- `ConfigPath`：配置文件路径（可选，默认为项目根目录的 config.toml）

**示例**：

```powershell
# 基本用法
Invoke-IpapCompleteWorkflow

# 带详细日志
Invoke-IpapCompleteWorkflow -Verbose

# 模拟执行（不实际处理文件）
Invoke-IpapCompleteWorkflow -WhatIf

# 自定义配置文件
Invoke-IpapCompleteWorkflow -ConfigPath "D:\path\to\config.toml"
```

### Invoke-IpapWorkflow

执行完整的工作流，包括图像高清化、WebP 转换和文件归档。

**参数**：
- `SourceDirectory`：源图像目录路径（必需）
- `ConfigPath`：配置文件路径（可选，默认为项目根目录的 config.toml）
- `UpscaleRatio`：放大倍数（可选，默认为配置文件中的值）
- `ModelSelect`：模型选择（可选，默认为配置文件中的值）

**示例**：

```powershell
# 基本用法
Invoke-IpapWorkflow -SourceDirectory "D:\path\to\images"

# 带详细日志
Invoke-IpapWorkflow -SourceDirectory "D:\path\to\images" -Verbose

# 模拟执行（不实际处理文件）
Invoke-IpapWorkflow -SourceDirectory "D:\path\to\images" -WhatIf

# 自定义配置
Invoke-IpapWorkflow -SourceDirectory "D:\path\to\images" -ConfigPath "D:\path\to\config.toml" -UpscaleRatio 2 -ModelSelect "models-se"
```

### New-IpapProjectStructure

创建项目目录结构。

**参数**：
- `BaseDirectory`：基础目录
- `ProjectName`：项目名称

**示例**：

```powershell
New-IpapProjectStructure -BaseDirectory "D:\projects" -ProjectName "测试项目"
```

### Get-IpapProjectInfo

获取项目信息。

**示例**：

```powershell
$briefText, $projectName = Get-IpapProjectInfo
```

### Copy-IpapImagesAndAnalyze

复制图片并分析。

**参数**：
- `SourcePath`：源路径
- `ProjectDirectory`：项目目录

**示例**：

```powershell
$imageFiles, $imageCount, $totalSize, $maxSize = Copy-IpapImagesAndAnalyze -SourcePath "D:\path\to\images" -ProjectDirectory "D:\projects\2024-01-01_测试项目"
```

### Process-IpapImages

处理图片。

**参数**：
- `ImageFiles`：图片文件列表
- `ProjectDirectory`：项目目录
- `Settings`：设置
- `AverageSizeKB`：平均大小（KB）

**示例**：

```powershell
Process-IpapImages -ImageFiles $imageFiles -ProjectDirectory "D:\projects\2024-01-01_测试项目" -Settings $config -AverageSizeKB 500
```

### New-IpapProjectFiles

创建项目文件。

**参数**：
- `ProjectDirectory`：项目目录
- `BriefText`：简介文本
- `ProjectName`：项目名称
- `ImageCount`：图片数量
- `AverageSizeKB`：平均大小（KB）

**示例**：

```powershell
New-IpapProjectFiles -ProjectDirectory "D:\projects\2024-01-01_测试项目" -BriefText $briefText -ProjectName "测试项目" -ImageCount 10 -AverageSizeKB 500
```

### Set-IpapProject

设置项目。

**参数**：
- `Settings`：设置

**示例**：

```powershell
$srcPath, $briefText, $projectName, $projDir = Set-IpapProject -Settings $config
```

### Move-IpapOriginalSource

归档原始文件到指定目录。

**参数**：
- `SourceFile`：源文件对象（必需）
- `ArchiveDirectory`：归档目录路径（必需）

**示例**：

```powershell
# 归档单个文件
$sourceFile = Get-ChildItem -Path "D:\path\to\image.jpg"
Move-IpapOriginalSource -SourceFile $sourceFile -ArchiveDirectory "D:\path\to\archive"

# 模拟执行
Move-IpapOriginalSource -SourceFile $sourceFile -ArchiveDirectory "D:\path\to\archive" -WhatIf
```

### Get-IpapImageInfo

分析图片文件属性。

**参数**：
- `ImageFiles`：图片文件对象数组（必需）

**示例**：

```powershell
# 分析图片
$imageFiles = Get-IpapImageFiles -DirectoryPath "D:\path\to\images"
$imageInfo = Get-IpapImageInfo -ImageFiles $imageFiles
Write-Host "找到 $($imageInfo.Count) 张图片，总大小: $([math]::Round($imageInfo.TotalSize / 1MB, 2)) MB"
```

### Convert-IpapImageToWebP

将图像转换为 WebP 格式。

**参数**：
- `ImagePath`：图像文件路径（必需）
- `OutputDirectory`：输出目录路径（必需）
- `CwebpPath`：cwebp.exe 工具路径（可选）

**示例**：

```powershell
# 转换单个图像
Convert-IpapImageToWebP -ImagePath "D:\path\to\image.jpg" -OutputDirectory "D:\path\to\output"
```

## 并行处理配置

模块支持并行处理多个图像，以提高处理效率。并行处理的并发数由配置文件中的 `max_workers` 参数控制：

```toml
[app_settings]
# 并行处理高清化任务的最大进程数
max_workers = 8
```

建议根据系统的 CPU 核心数和内存大小来设置合适的并发数，以避免系统资源超载。

## 常见问题

### 1. 模块初始化失败

**原因**：可能是 PowerShell-TOML 模块未安装。

**解决方案**：模块会自动尝试安装 PowerShell-TOML 模块。如果自动安装失败，请手动安装：

```powershell
Install-Module -Name PowerShell-TOML -Scope CurrentUser -Force
```

### 2. 高清化处理失败

**原因**：可能是 realcugan-ncnn-vulkan 可执行文件不存在或路径错误。

**解决方案**：确保 realcugan-ncnn-vulkan.exe 文件存在于 `powershell/realcugan-ncnn-vulkan-20220728-windows/` 目录中。

### 3. WebP 转换失败

**原因**：可能是 cwebp.exe 工具不存在，且 .NET 方法不支持 WebP 格式。

**解决方案**：下载 Google 官方的 cwebp.exe 工具，并放置在 `powershell/` 目录中。

### 4. 文件归档失败

**原因**：可能是归档目录不存在或权限不足。

**解决方案**：确保归档目录存在，且当前用户有写入权限。

## 故障排除

### 启用详细日志

使用 `-Verbose` 参数可以查看详细的日志信息，帮助定位问题：

```powershell
Invoke-IpapWorkflow -SourceDirectory "D:\path\to\images" -Verbose
```

### 模拟执行

使用 `-WhatIf` 参数可以模拟执行过程，查看将要执行的操作，而不会实际修改文件：

```powershell
Invoke-IpapWorkflow -SourceDirectory "D:\path\to\images" -WhatIf
```

## 示例工作流

### 完整工作流（推荐）

```powershell
# 导入模块
Import-Module -Name "D:\documents\code\IPAP_workflow\powershell\ipap_workflow.psd1"

# 执行完整工作流（包括项目设置、图片处理、文档创建）
Invoke-IpapCompleteWorkflow -Verbose
```

### 传统工作流

```powershell
# 导入模块
Import-Module -Name "D:\documents\code\IPAP_workflow\powershell\ipap_workflow.psd1"

# 执行工作流
Invoke-IpapWorkflow -SourceDirectory "D:\path\to\images" -Verbose
```

### 自定义配置工作流

```powershell
# 导入模块
Import-Module -Name "D:\documents\code\IPAP_workflow\powershell\ipap_workflow.psd1"

# 执行工作流（自定义放大倍数和模型）
Invoke-IpapWorkflow -SourceDirectory "D:\path\to\images" -UpscaleRatio 3 -ModelSelect "models-pro" -Verbose
```

### 批量处理多个文件夹

```powershell
# 导入模块
Import-Module -Name "D:\documents\code\IPAP_workflow\powershell\ipap_workflow.psd1"

# 定义要处理的文件夹列表
$folders = @(
    "D:\path\to\folder1",
    "D:\path\to\folder2",
    "D:\path\to\folder3"
)

# 批量处理每个文件夹
foreach ($folder in $folders) {
    Write-Host "处理文件夹: $folder"
    Invoke-IpapWorkflow -SourceDirectory $folder -Verbose
    Write-Host "----------------------------------------"
}
```

### 自定义项目结构

```powershell
# 导入模块
Import-Module -Name "D:\documents\code\IPAP_workflow\powershell\ipap_workflow.psd1"

# 创建自定义项目结构
$baseDir = "D:\custom\projects"
$projectName = "我的自定义项目"
New-IpapProjectStructure -BaseDirectory $baseDir -ProjectName $projectName

# 获取项目目录
$projectDir = Join-Path -Path $baseDir -ChildPath "$((Get-Date).ToString('yyyy-MM-dd'))_$projectName"

# 复制并分析图片
$sourcePath = "D:\path\to\images"
$imageFiles, $imageCount, $totalSize, $maxSize = Copy-IpapImagesAndAnalyze -SourcePath $sourcePath -ProjectDirectory $projectDir

# 处理图片
$config = @{
    upscale = @{
        upscale_ratio = 2
        noise_level = 0
    }
    app_settings = @{
        max_workers = 4
        model_select = "models-se"
    }
    webp = @{
        enabled = $true
        lossless = $true
    }
}
Process-IpapImages -ImageFiles $imageFiles -ProjectDirectory $projectDir -Settings $config -AverageSizeKB ([math]::Round($totalSize / $imageCount, 2))

# 创建项目文件
$briefText = "这是一个自定义项目示例"
New-IpapProjectFiles -ProjectDirectory $projectDir -BriefText $briefText -ProjectName $projectName -ImageCount $imageCount -AverageSizeKB ([math]::Round($totalSize / $imageCount, 2))

Write-Host "项目处理完成: $projectDir"
```

## 性能优化

1. **并行处理**：根据系统资源合理设置 `max_workers` 参数，以充分利用系统资源。
2. **批量处理**：对于大量图像，建议分批处理，以避免内存不足。
3. **磁盘空间**：确保目标磁盘有足够的空间，特别是在处理大量高分辨率图像时。
4. **系统资源**：关闭不必要的应用程序，以释放系统资源。

## 许可证

本模块采用 MIT 许可证。
