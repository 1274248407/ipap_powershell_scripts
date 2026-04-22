<#
.SYNOPSIS
    IPAP 工作流项目管理模块
.DESCRIPTION
    提供项目目录结构创建、README 文件生成和翻译文件管理功能。
#>

Import-Module "$PSScriptRoot\..\IPAP.Core\IPAP.Core.psm1" -Force

<#
.SYNOPSIS
    创建项目目录结构
.DESCRIPTION
    创建符合 IPAP 工作流标准的项目目录结构，包括预处理、翻译和排版目录。
.PARAMETER BaseDir
    项目基础目录。
.PARAMETER ProjectName
    项目名称。
.EXAMPLE
    New-ProjectStructure -BaseDir "C:\Projects" -ProjectName "Manga1"
    在 C:\Projects 目录下创建名为 2026-04-20_Manga1 的项目目录。
#>
function New-ProjectStructure {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseDir,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName
    )

    $today = Get-Date -Format "yyyy-MM-dd"
    $projectDirName = "${today}_${ProjectName}"
    $projectDir = Join-Path $BaseDir $projectDirName

    if (Test-Path $projectDir) {
        $response = Read-Host "Directory $projectDir already exists, overwrite? (Y/N)"
        if ($response -ne "Y" -and $response -ne "y") {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$timestamp] [INFO] User cancelled overwrite operation" -ForegroundColor Cyan
            return $null
        }
    }

    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [INFO] Creating project directory: $projectDir" -ForegroundColor Cyan

        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null

        $subDirs = @(
            "02_Preprocessing\raw_source",
            "02_Preprocessing\original_non_text_raw",
            "02_Preprocessing\inpainted",
            "02_Preprocessing\mask",
            "03_Translation",
            "04_Typesetting\workfiles",
            "04_Typesetting\final_pages"
        )

        foreach ($subDir in $subDirs) {
            $fullPath = Join-Path $projectDir $subDir
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$timestamp] [INFO] Created subdirectory: $fullPath" -ForegroundColor Cyan
        }

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [SUCCESS] Project directory structure created successfully" -ForegroundColor Green
        return $projectDir
    } catch {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] Failed to create project directory: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

<#
.SYNOPSIS
    创建 README.md 文件
.DESCRIPTION
    根据项目配置和日期信息生成 README.md 文件，包含项目基本信息、进度跟踪和处理笔记等模板内容。
.PARAMETER ProjectDir
    项目根目录路径。
.PARAMETER ProjectName
    项目名称。
.PARAMETER ImageCount
    原始文件数量。
.PARAMETER NeedUpscale
    是否需要高清化处理。
.PARAMETER UpscaleRatio
    高清化倍数。
.EXAMPLE
    New-ReadmeFile -ProjectDir "C:\Projects\Manga1" -ProjectName "Manga1" -ImageCount 50 -NeedUpscale `$true -UpscaleRatio 2
    在项目目录下创建包含高清化状态的 README.md 文件。
#>
function New-ReadmeFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,
        [Parameter(Mandatory = $true)]
        [int]$ImageCount,
        [Parameter(Mandatory = $true)]
        [bool]$NeedUpscale,
        [int]$UpscaleRatio = 2
    )

    $today = Get-Date -Format "yyyy-MM-dd"
    $upscaleStatus = if ($NeedUpscale) { "X" } else { " " }
    $upscaleRatioText = if ($NeedUpscale) { $UpscaleRatio.ToString() } else { "N/A" }

    $content = @"
# 项目记录: ${ProjectName} (${today})

## 项目基本信息
- 原始文件数量: ${ImageCount} 张
- 原始文件是否需要高清化: [${upscaleStatus}]
- 使用高清化倍数: ${upscaleRatioText}
## 进度跟踪
- [ ] 文件整理与分离
- [ ] OCR 处理与校对
- [ ] Inpainting 处理与修正
- [ ] 文本翻译
- [ ] 嵌字 (完成至页 X)
- [ ] 最终质量检查

## 处理笔记与特殊情况
### 预处理阶段

### 翻译阶段

### 嵌字阶段

## 待办/提醒

## 其他
- [任何你想记下的其他信息]
"@

    try {
        $readmePath = Join-Path $ProjectDir "README.md"
        $content | Out-File -FilePath $readmePath -Encoding UTF8
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [SUCCESS] README.md file created successfully" -ForegroundColor Green
    } catch {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] Failed to create README.md file: $($_.Exception.Message)" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    创建翻译相关文件
.DESCRIPTION
    在项目目录下创建 03_Translation 文件夹，并生成项目简介文件和词汇表文件。
.PARAMETER ProjectDir
    项目根目录路径。
.PARAMETER BriefText
    项目简介文本（可选）。
.EXAMPLE
    New-TranslationFiles -ProjectDir "C:\Projects\Manga1"
    创建翻译文件夹和空词汇表文件。
.EXAMPLE
    New-TranslationFiles -ProjectDir "C:\Projects\Manga1" -BriefText "这是一个漫画翻译项目"
    创建翻译文件夹并包含项目简介。
#>
function New-TranslationFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,
        [string]$BriefText = $null
    )

    try {
        $translationDir = Join-Path $ProjectDir "03_Translation"

        if (-not (Test-Path $translationDir)) {
            New-Item -ItemType Directory -Path $translationDir -Force | Out-Null
        }

        $briefFile = Join-Path $translationDir "project_brief.md"
        if ($BriefText) {
            $BriefText | Out-File -FilePath $briefFile -Encoding UTF8
        }

        $glossaryFile = Join-Path $translationDir "glossary.json"
        "{}" | Out-File -FilePath $glossaryFile -Encoding UTF8

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [SUCCESS] Translation files created successfully" -ForegroundColor Green
    } catch {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Host "[$timestamp] [ERROR] Failed to create translation files: $($_.Exception.Message)" -ForegroundColor Red
    }
}

<#
.SYNOPSIS
    提示用户输入项目相关的多行信息并格式化
.DESCRIPTION
    提示用户输入项目名称、作品中文译名和多行项目简介，
    然后将这些信息按照特定模板格式化为一个字符串，并返回格式化后的
    字符串和项目名称。
.EXAMPLE
    Get-ProjectBriefInfo
    获取项目简介信息并返回格式化后的字符串和项目名称。
#>
function Get-ProjectBriefInfo {
    [CmdletBinding()]
    param ()

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] === 项目信息输入 ===" -ForegroundColor Cyan

    $projectName = Read-Host "项目名称（格式：[作者] 原作品名）"
    $projectName = $projectName.Trim()

    $authorChinese = Read-Host "作品中文译名"
    $authorChinese = $authorChinese.Trim()

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [INFO] 请输入【项目简介】（多行，空行结束）：" -ForegroundColor Cyan
    $overviewLines = @()
    while ($true) {
        $line = Read-Host
        if (-not $line.Trim()) {
            break
        }
        $overviewLines += $line
    }

    $tpl = @(
        "项目名称 ：$projectName | $authorChinese",
        "；",
        "项目简介 ：{世界观概述：",
        $overviewLines,
        "；本地化目标（如文化适配方向或语言风格定位），总字数≤200字}",
        "；",
        "角色译名表 ：原名|中文译名|{身份标签}（按需增行）",
        "；",
        "名词对照表 ：标签:原文:译名|补充说明（支持新增标签）"
    )

    $formatted = $tpl -join "`n" + "`n"

    return $formatted, $projectName
}

Export-ModuleMember -Function @(
    "New-ProjectStructure",
    "New-ReadmeFile",
    "New-TranslationFiles",
    "Get-ProjectBriefInfo"
)
