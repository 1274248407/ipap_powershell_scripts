<#
.SYNOPSIS
    IPAP 构建脚本
.DESCRIPTION
    函数化构建脚本，支持 Task 依赖图调度。提供以下 Task：
    - Build：构建模块到 output/IPAP/
    - Analyze：PSScriptAnalyzer 静态检查
    - Test：Pester v5 测试（单元 + 集成）+ 代码覆盖率（JaCoCo）
    - Pack：打包发布 zip（强制前置 Build/Analyze/Test）
    - Release：git commit/tag/push + gh release create（强制前置 Pack）

    Task 依赖图：
    - Build     -> （无）
    - Analyze   -> （无）
    - Test      -> Build, Analyze
    - Pack      -> Build, Analyze, Test
    - Release   -> Pack

    调度器自动按依赖顺序执行，已跑过的 Task 不重复跑。
.PARAMETER Task
    (string[]) 要执行的 Task 列表（必填）。可选值：Build、Analyze、Test、Pack、Release。
    前置依赖会自动触发，例如 -Task Pack 会依次执行 Build、Analyze、Test。
.PARAMETER ResolveDependency
    (switch) 是否解析外部依赖（PSToml），默认 $true。幂等：已安装则跳过。
.PARAMETER UseModuleFast
    (switch) 是否优先使用 ModuleFast 加速依赖下载，默认 $true。
    ModuleFast 不可用时自动回退到 Save-Module。
.EXAMPLE
    .\build.ps1 -Task Build
    # 仅构建
.EXAMPLE
    .\build.ps1 -Task Test
    # 自动触发 Build + Analyze + Test
.EXAMPLE
    .\build.ps1 -Task Pack
    # 自动触发 Build + Analyze + Test + Pack（全套 + 打包）
.EXAMPLE
    .\build.ps1 -Task Release
    # 自动触发全套 + 打包 + 发布（git commit/tag/push + gh release）
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
# 屏蔽 PSAvoidDefaultValueSwitchParameter：build.ps1 是项目专用构建脚本，
# $ResolveDependency/$UseModuleFast 默认 $true 确保依赖自动解析，避免用户忘记传参
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidDefaultValueSwitchParameter', '')]
param (
    [Parameter(Mandatory)]
    [ValidateSet('Build', 'Analyze', 'Test', 'Pack', 'Release')]
    [string[]] $Task,
    [switch] $ResolveDependency = $true,
    [switch] $UseModuleFast = $true
)

$ErrorActionPreference = 'Stop'

# 路径常量
$script:ModulePath = $PSScriptRoot
$script:SourcePath = Join-Path -Path $script:ModulePath -ChildPath 'source'
$script:OutputPath = Join-Path -Path $script:ModulePath -ChildPath 'output'
$script:RequiredModulesPath = Join-Path -Path $script:OutputPath -ChildPath 'RequiredModules'
$script:ModuleName = 'IPAP'

# Task 依赖图（声明式拓扑结构）
$script:TaskDependencies = @{
    Build   = @()
    Analyze = @()
    Test    = @('Build', 'Analyze')
    Pack    = @('Build', 'Analyze', 'Test')
    Release = @('Pack')
}

# 已执行的 Task 集合（用于调度器去重）
$script:ExecutedTasks = @{}

<#
.SYNOPSIS
    解析外部依赖（PSToml）
.DESCRIPTION
    使用 Save-Module 或 ModuleFast 将外部模块下载到 output/RequiredModules/。
    幂等：模块已存在则跳过。ModuleFast 不可用时自动回退到 Save-Module。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-ResolveDependency
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    Write-Output '解析外部依赖项...'

    # 外部依赖清单（TOML 解析库）
    $requiredModules = @(
        @{
            Name    = 'PSToml'
            Version = '0.5.0'
        }
    )

    # 检测 ModuleFast 是否可用
    $moduleFastAvailable = $null -ne (Get-Command -Name 'Save-ModuleFast' -ErrorAction SilentlyContinue)

    foreach ($module in $requiredModules)
    {
        # 构建模块输出路径
        $moduleOutputPath = Join-Path -Path $script:RequiredModulesPath -ChildPath $module.Name
        if (-not (Test-Path -LiteralPath $moduleOutputPath))
        {
            Write-Output "安装 $($module.Name) $($module.Version)..."
            if ($UseModuleFast -and $moduleFastAvailable)
            {
                Save-ModuleFast -Name $module.Name -Version $module.Version -Path $script:RequiredModulesPath -Force
            }
            else
            {
                if ($UseModuleFast -and -not $moduleFastAvailable)
                {
                    Write-Warning 'ModuleFast 不可用，回退到 Save-Module'
                }
                Save-Module -Name $module.Name -RequiredVersion $module.Version -Path $script:RequiredModulesPath -Force
            }
        }
        else
        {
            Write-Output "$($module.Name) 已存在，跳过"
        }
    }
}

<#
.SYNOPSIS
    构建模块到 output/IPAP/
.DESCRIPTION
    将 source/ 目录内容复制到 output/IPAP/。
    若输出目录已存在则先清空。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-BuildTask
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    Write-Output '构建模块...'

    # 构建输出路径
    $buildOutputPath = Join-Path -Path $script:OutputPath -ChildPath $script:ModuleName

    # 清空旧构建产物
    if (Test-Path -LiteralPath $buildOutputPath)
    {
        Remove-Item -LiteralPath $buildOutputPath -Recurse -Force
    }

    # 创建输出目录
    New-Item -ItemType Directory -Path $buildOutputPath -Force | Out-Null

    # 复制 source/ 内容到输出目录
    Copy-Item -Path (Join-Path -Path $script:SourcePath -ChildPath '*') -Destination $buildOutputPath -Recurse -Force -ErrorAction Stop

    Write-Output "模块构建完成：$buildOutputPath"
}

<#
.SYNOPSIS
    PSScriptAnalyzer 静态分析
.DESCRIPTION
    对项目内所有 .ps1/.psm1/.psd1 文件运行 PSScriptAnalyzer，
    排除 output/.git/node_modules/tests 路径与 build.ps1 本身。
    发现任何问题立即报错退出。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-AnalyzeTask
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    Write-Output '运行静态分析...'

    # 收集待分析文件（排除 output/.git/node_modules/tests 和 build.ps1 本身）
    $analysisFiles = Get-ChildItem -Path $script:ModulePath -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
        Where-Object { $PSItem.FullName -notmatch 'output|.git|node_modules|tests' -and $PSItem.Name -ne 'build.ps1' }

    # 逐文件运行分析器
    $results = @()
    foreach ($File in $analysisFiles)
    {
        $results += Invoke-ScriptAnalyzer -Path $File.FullName -Settings (Join-Path -Path $script:ModulePath -ChildPath 'PSScriptAnalyzerSettings.psd1')
    }

    # Error/Warning 级阻断；Information 级仅展示不阻断（参考性规则如 PSUseOutputTypeCorrectly 存在静态误报）
    $blocking = $results | Where-Object { $PSItem.Severity -in @('Error', 'Warning') }
    if ($blocking)
    {
        Write-Output "`n静态分析发现问题："
        $results | Format-Table -Property RuleName, Severity, @{n = 'Path'; e = { $PSItem.ScriptPath.Split('\')[-1] } }, Line, Message -AutoSize
        Write-Error '静态分析未通过'
        exit 1
    }
    # Information 级问题展示但不阻断
    if ($results)
    {
        Write-Output "`n静态分析提示（Information 级，不阻断）："
        $results | Format-Table -Property RuleName, @{n = 'Path'; e = { $PSItem.ScriptPath.Split('\')[-1] } }, Line, Message -AutoSize | Out-String -Stream | Select-Object -First 15
    }
    Write-Output '静态分析通过'

    # 函数必须声明 [OutputType()] 的项目契约防线（规则文件第 1 章标准架构）
    Invoke-OutputTypeAudit
}

<#
.SYNOPSIS
    检查所有函数是否声明 OutputType 属性
.DESCRIPTION
    基于 AST 解析 source/Public 与 source/Private 下的全部 .ps1 文件，
    验证每个函数的 param 块均包含 [OutputType()] 声明。
    类方法不适用 OutputType 属性（返回契约由方法签名的静态类型承担），予以豁免。
    发现缺失时列明位置并终止构建。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-OutputTypeAudit
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    # 收集待检查文件（Public + Private，一函数一文件）
    $auditFiles = Get-ChildItem -Path (Join-Path -Path $script:SourcePath -ChildPath 'Public'), (Join-Path -Path $script:SourcePath -ChildPath 'Private') -Filter '*.ps1'

    # 收集缺失 OutputType 声明的条目
    $missing = @()
    foreach ($File in $auditFiles)
    {
        $tokens = $null
        $parseErrors = $null
        # 解析文件 AST 并查找全部函数定义
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$tokens, [ref]$parseErrors)
        $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

        foreach ($Function in $functions)
        {
            # 提取 param 块 attribute 类型名，检查是否声明 OutputType
            $attrNames = @($Function.Body.ParamBlock.Attributes | ForEach-Object { $PSItem.TypeName.Name })
            if (-not ($attrNames -contains 'OutputType'))
            {
                $missing += '{0} 行 {1}：函数 {2} 缺少 [OutputType()] 声明' -f $File.Name, $Function.Extent.StartLineNumber, $Function.Name
            }
        }
    }

    # 发现缺失则报错退出
    if ($missing.Count -gt 0)
    {
        Write-Output "`n以下函数缺少 [OutputType()] 声明："
        $missing | ForEach-Object { Write-Output $PSItem }
        Write-Error 'OutputType 契约检查未通过'
        exit 1
    }
    Write-Output 'OutputType 契约检查通过'
}

<#
.SYNOPSIS
    Pester v5 测试 + 代码覆盖率
.DESCRIPTION
    运行 tests/ 目录下所有 *.Tests.ps1（单元 + 集成），启用 JaCoCo 代码覆盖率，
    输出 coverage.xml 到 output/。
    任何测试失败立即报错退出。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-TestTask
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    Write-Output '运行测试（单元 + 集成）...'

    # 源文件 glob（用于覆盖率统计）
    $sourceGlob = Join-Path -Path $script:SourcePath -ChildPath '*\*.ps1'

    # Pester 配置
    $pesterConfig = New-PesterConfiguration -Hashtable @{
        Run          = @{
            Path     = (Join-Path -Path $script:ModulePath -ChildPath 'tests')
            PassThru = $true
        }
        CodeCoverage = @{
            Enabled      = $true
            Path         = @($sourceGlob)
            OutputFormat = 'JaCoCo'
            OutputPath   = (Join-Path -Path $script:OutputPath -ChildPath 'coverage.xml')
        }
    }

    # 运行测试
    $testResults = Invoke-Pester -Configuration $pesterConfig
    if ($testResults.FailedCount -gt 0)
    {
        Write-Error '测试未通过'
        exit 1
    }

    # 覆盖率报告路径
    $coverageReportPath = Join-Path -Path $script:OutputPath -ChildPath 'coverage.xml'
    Write-Output '所有测试通过'
    Write-Output "覆盖率报告：$coverageReportPath"
}

<#
.SYNOPSIS
    读取并报告代码覆盖率
.DESCRIPTION
    解析 output/coverage.xml（JaCoCo 格式），提取报告级 LINE counter，
    计算并输出总覆盖率百分比（仅供参考，暂不强制 100% 门禁）。
    报告缺失时报错退出。
.OUTPUTS
    [double] 当前覆盖率百分比
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Test-CodeCoverage
{
    [CmdletBinding()]
    [OutputType([double])]
    param ()

    # 覆盖率报告路径
    $coverageReportPath = Join-Path -Path $script:OutputPath -ChildPath 'coverage.xml'
    if (-not (Test-Path -LiteralPath $coverageReportPath))
    {
        Write-Error "覆盖率报告不存在：$coverageReportPath（请先运行 Test task）"
        exit 1
    }

    # 解析 JaCoCo XML
    [xml]$coverageXml = Get-Content -LiteralPath $coverageReportPath -Raw -Encoding utf8

    # 提取报告级 LINE counter（JaCoCo 在 <report> 直属子节点有汇总 counter）
    $lineCounter = $coverageXml.report.counter | Where-Object { $PSItem.type -eq 'LINE' } | Select-Object -First 1
    if (-not $lineCounter)
    {
        Write-Error '覆盖率报告未找到 LINE 类型 counter'
        exit 1
    }

    # 计算覆盖率
    [int]$missed = [int]$lineCounter.missed
    [int]$covered = [int]$lineCounter.covered
    [int]$total = $missed + $covered
    [double]$coveragePercent = if ($total -gt 0) { ($covered / $total) * 100 } else { 0 }

    # 输出覆盖率（暂不强制 100% 门禁，迁移期仅报告）
    Write-Output "代码覆盖率：$([Math]::Round($coveragePercent, 2))%（覆盖 $covered 行，未覆盖 $missed 行）"
    return $coveragePercent
}

<#
.SYNOPSIS
    读取 psd1 模块清单中的 ModuleVersion
.DESCRIPTION
    解析 source/IPAP.psd1，返回 ModuleVersion 字段值（如 '1.0.0'）。
.OUTPUTS
    [string] 版本号字符串
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-ModuleVersion
{
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    # psd1 路径
    $psd1Path = Join-Path -Path $script:SourcePath -ChildPath "$($script:ModuleName).psd1"
    if (-not (Test-Path -LiteralPath $psd1Path))
    {
        Write-Error "模块清单不存在：$psd1Path"
        exit 1
    }

    # 解析 psd1 内容
    $manifest = Import-PowerShellDataFile -LiteralPath $psd1Path
    [string]$version = $manifest.ModuleVersion
    if ([string]::IsNullOrEmpty($version))
    {
        Write-Error 'psd1 中未找到 ModuleVersion'
        exit 1
    }

    return $version
}

<#
.SYNOPSIS
    打包发布 zip
.DESCRIPTION
    组装发布暂存目录，包含：模块代码（IPAP/）、Main.ps1、
    config.toml（由 config.toml.example 生成）、RequiredModules/PSToml。
    最终压缩为 output/IPAP-v<Version>.zip。

    前置校验：
    1. Build 产物存在（output/IPAP/）
    2. PSToml 已下载（output/RequiredModules/PSToml/）
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-PackTask
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    Write-Output '打包发布 zip...'

    # 步骤 1：校验 Build 产物
    $buildOutputPath = Join-Path -Path $script:OutputPath -ChildPath $script:ModuleName
    if (-not (Test-Path -LiteralPath $buildOutputPath))
    {
        Write-Error "Build 产物不存在：$buildOutputPath（请先运行 Build task）"
        exit 1
    }

    # 步骤 2：报告代码覆盖率（暂不强制门禁）
    $null = Test-CodeCoverage

    # 步骤 3：读取版本号
    [string]$version = Get-ModuleVersion
    Write-Output "版本号：$version"

    # 步骤 4：清空 + 创建暂存目录
    $stagingRoot = Join-Path -Path $script:OutputPath -ChildPath 'ReleaseStaging'
    $stagingPath = Join-Path -Path $stagingRoot -ChildPath "$($script:ModuleName)-v$version"
    if (Test-Path -LiteralPath $stagingPath)
    {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null

    # 步骤 5：复制模块代码（output/IPAP 内容 -> IPAP/）
    $moduleDirInZip = Join-Path -Path $stagingPath -ChildPath $script:ModuleName
    New-Item -ItemType Directory -Path $moduleDirInZip -Force | Out-Null
    Copy-Item -Path (Join-Path -Path $buildOutputPath -ChildPath '*') -Destination $moduleDirInZip -Recurse -Force -ErrorAction Stop

    # 步骤 6：复制 Main.ps1 入口脚本
    $mainPs1SourcePath = Join-Path -Path $script:ModulePath -ChildPath 'Main.ps1'
    $mainPs1DestPath = Join-Path -Path $stagingPath -ChildPath 'Main.ps1'
    Copy-Item -Path $mainPs1SourcePath -Destination $mainPs1DestPath -Force -ErrorAction Stop

    # 步骤 7：复制配置模板为 config.toml（发布包内自带默认配置，用户按需修改）
    $configSourcePath = Join-Path -Path $script:ModulePath -ChildPath 'config.toml.example'
    if (-not (Test-Path -LiteralPath $configSourcePath))
    {
        Write-Error "配置模板不存在：$configSourcePath"
        exit 1
    }
    $configDestPath = Join-Path -Path $stagingPath -ChildPath 'config.toml'
    Copy-Item -Path $configSourcePath -Destination $configDestPath -Force -ErrorAction Stop

    # 步骤 8：复制 RequiredModules/PSToml
    $pstomlSourcePath = Join-Path -Path $script:RequiredModulesPath -ChildPath 'PSToml'
    if (-not (Test-Path -LiteralPath $pstomlSourcePath))
    {
        Write-Error "PSToml 未下载：$pstomlSourcePath（请用 -ResolveDependency 运行）"
        exit 1
    }
    $pstomlDestPath = Join-Path -Path $stagingPath -ChildPath 'RequiredModules\PSToml'
    New-Item -ItemType Directory -Path (Split-Path -Path $pstomlDestPath -Parent) -Force | Out-Null
    Copy-Item -Path $pstomlSourcePath -Destination $pstomlDestPath -Recurse -Force -ErrorAction Stop

    # 步骤 9：压缩 zip
    $zipPath = Join-Path -Path $script:OutputPath -ChildPath "$($script:ModuleName)-v$version.zip"
    if (Test-Path -LiteralPath $zipPath)
    {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path -Path $stagingPath -ChildPath '*') -DestinationPath $zipPath -Force

    # 打印总结
    Write-Output ''
    Write-Output '=========================================='
    Write-Output '打包完成'
    Write-Output "  版本号：v$version"
    Write-Output "  zip 路径：$zipPath"
    Write-Output "  暂存目录：$stagingPath"
    Write-Output '=========================================='
}

<#
.SYNOPSIS
    发布到 GitHub Release
.DESCRIPTION
    前置校验：Pack 产物 zip 存在、gh CLI 已安装。
    交互式 y/n 网关：用户确认后依次执行
    1. git add（精确文件列表，含删除的旧文件）
    2. git commit（中文 conventional commits 规范）
    3. git tag -a（带注释标签）
    4. git push origin <当前分支> --tags
    5. gh release create（zip + 标题 + notes）
    任何步骤失败立即 exit 1。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-ReleaseTask
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    Write-Output '发布到 GitHub Release...'

    # 步骤 1：读取版本号
    [string]$version = Get-ModuleVersion

    # 步骤 2：校验 zip 存在
    $zipPath = Join-Path -Path $script:OutputPath -ChildPath "$($script:ModuleName)-v$version.zip"
    if (-not (Test-Path -LiteralPath $zipPath))
    {
        Write-Error "Pack 产物不存在：$zipPath（请先运行 Pack task）"
        exit 1
    }

    # 步骤 3：校验 gh CLI 已安装
    if ($null -eq (Get-Command -Name 'gh' -ErrorAction SilentlyContinue))
    {
        Write-Error 'GitHub CLI 未安装，请先安装：https://cli.github.com/'
        exit 1
    }

    # 获取当前分支名（推送目标）
    $currentBranch = git branch --show-current

    # 步骤 4：打印发布清单
    Write-Output ''
    Write-Output '=========================================='
    Write-Output '发布清单'
    Write-Output "  版本号：v$version"
    Write-Output "  zip 路径：$zipPath"
    Write-Output "  推送分支：$currentBranch"
    Write-Output '=========================================='
    Write-Output ''
    Write-Output '即将执行：'
    Write-Output '  1. git add .（暂存全部变更）'
    Write-Output "  2. git commit -m `"chore(release): v$version`""
    Write-Output "  3. git tag -a v$version -m 'Release v$version'"
    Write-Output "  4. git push origin $currentBranch --tags"
    Write-Output '  5. gh release create'
    Write-Output ''

    # 步骤 5：y/n 网关（不可逆操作前必须确认）
    $confirmation = Read-Host -Prompt '确认执行 commit + tag + push + gh release？(y/n)'
    if ($confirmation -ne 'y' -and $confirmation -ne 'Y')
    {
        Write-Output '已中止发布。zip 保留在 output/ 目录。'
        return
    }

    # 步骤 6：执行 git 操作
    Write-Output '暂存变更...'
    $null = & git add .
    if ($LASTEXITCODE -ne 0)
    {
        Write-Error 'git add 失败'
        exit 1
    }

    # 显示暂存区状态
    Write-Output '暂存区状态：'
    $null = & git status --short

    # 提交
    Write-Output '提交 commit...'
    $commitMessage = "chore(release): v$version 稳定发布"
    $null = & git commit -m $commitMessage
    if ($LASTEXITCODE -ne 0)
    {
        Write-Error 'git commit 失败'
        exit 1
    }

    # 打 tag
    Write-Output "打 tag v$version..."
    $tagMessage = "Release v$version : IPAP 漫画翻译准备工具稳定发布"
    $null = & git tag -a "v$version" -m $tagMessage
    if ($LASTEXITCODE -ne 0)
    {
        Write-Error "git tag v$version 失败"
        exit 1
    }

    # 推送 commit + tag
    Write-Output "推送 commit 和 tag 到 origin/$currentBranch..."
    $null = & git push origin $currentBranch --tags
    if ($LASTEXITCODE -ne 0)
    {
        Write-Error 'git push 失败'
        exit 1
    }

    # 步骤 7：创建 GitHub Release
    Write-Output '创建 GitHub Release...'
    $releaseTitle = "v$version"
    $releaseNotes = "IPAP v$version 发布。详见仓库文档。"
    $null = & gh release create "v$version" $zipPath --title $releaseTitle --notes $releaseNotes
    if ($LASTEXITCODE -ne 0)
    {
        Write-Error 'gh release create 失败'
        exit 1
    }

    Write-Output ''
    Write-Output '=========================================='
    Write-Output "发布成功 v$version"
    Write-Output "  Release URL：https://github.com/1274248407/ipap_powershell_scripts/releases/tag/v$version"
    Write-Output '=========================================='
}

<#
.SYNOPSIS
    Task 调度器（按依赖图递归执行）
.DESCRIPTION
    根据 $script:TaskDependencies 递归执行前置依赖，
    再执行当前 Task。已跑过的 Task 跳过避免重复。
.PARAMETER TaskName
    (string) 要执行的 Task 名称
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-TaskWithDependency
{
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TaskName
    )

    # 校验 Task 名是否在依赖图中
    if (-not $script:TaskDependencies.ContainsKey($TaskName))
    {
        Write-Error "未知 Task：$TaskName（可用 Task：$($script:TaskDependencies.Keys -join ', ')）"
        exit 1
    }

    # 已执行过则跳过
    if ($script:ExecutedTasks.ContainsKey($TaskName))
    {
        return
    }

    # 递归执行前置依赖
    foreach ($dependency in $script:TaskDependencies[$TaskName])
    {
        Invoke-TaskWithDependency -TaskName $dependency
    }

    # 执行当前 Task
    Write-Output ''
    Write-Output "==> 执行 Task：$TaskName"
    switch ($TaskName)
    {
        'Build' { Invoke-BuildTask }
        'Analyze' { Invoke-AnalyzeTask }
        'Test' { Invoke-TestTask }
        'Pack' { Invoke-PackTask }
        'Release' { Invoke-ReleaseTask }
    }

    # 标记为已执行
    $script:ExecutedTasks[$TaskName] = $true
}

# 入口：解析依赖 + 按 -Task 顺序执行
if ($ResolveDependency)
{
    Invoke-ResolveDependency
}

foreach ($taskName in $Task)
{
    Invoke-TaskWithDependency -TaskName $taskName
}

Write-Output ''
Write-Output '所有 Task 执行完成。'
