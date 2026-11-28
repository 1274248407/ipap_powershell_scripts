<#
.SYNOPSIS
    IPAP 构建脚本
.DESCRIPTION
    函数化构建脚本，支持 Task 依赖图调度。提供以下 Task：
    - Build：构建模块到 output/IPAP/
    - Analyze：PSScriptAnalyzer 静态检查
    - Format：按 PSScriptAnalyzerSettings.psd1 格式化源码（独立任务，会改写源码）
    - Test：Pester 测试（单元 + 集成 + 真实工具链冒烟）+ 代码覆盖率（JaCoCo）
    - Smoke：只跑真实工具链冒烟（依赖 GPU 与 bin/ 工具）
    - Pack：打包发布 zip（强制前置 Build/Analyze/Test）
    - Release：git commit/tag/push + gh release create（强制前置 Pack）

    Task 依赖图：
    - Build     -> （无）
    - Analyze   -> （无）
    - Format    -> （无；会改写源码，故不进入任何依赖链）
    - Test      -> Build, Analyze
    - Smoke     -> （无）
    - Pack      -> Build, Analyze, Test
    - Release   -> Pack

    调度器自动按依赖顺序执行，已跑过的 Task 不重复跑。
.PARAMETER Task
    (string[]) 要执行的 Task 列表（必填）。可选值：Build、Analyze、Format、Test、Smoke、Pack、Release。
    前置依赖会自动触发，例如 -Task Pack 会依次执行 Build、Analyze、Test。
    Format 不参与依赖链：它会改写源码，只在显式指定时执行。
.PARAMETER ResolveDependency
    (switch) 是否解析外部依赖（PSToml），默认 $true。幂等：已安装则跳过。
.PARAMETER UseModuleFast
    (switch) 是否优先使用 ModuleFast 加速依赖下载，默认 $true。
    ModuleFast 不可用时自动回退到 Save-Module。
.PARAMETER Bump
    (string) 按 SemVer 推进版本号：major / minor / patch。只与 Pack 或 Release 一起使用：
    先从最后一个版本 tag 算出新版本并写回 source/IPAP.psd1，再执行打包/发布。
    省略时按清单里的版本号执行，并由 Assert-VersionReady 做严格校验。
.PARAMETER Yes
    (switch) Release 时跳过 y/n 确认，用于脚本化发布（CI 或自动化）。
    交互发布时不要传，保留人工确认这一道关。
.EXAMPLE
    .\build.ps1 -Task Build
    # 仅构建
.EXAMPLE
    .\build.ps1 -Task Release -Bump minor
    # 版本号按 minor 推进后，走完整套 + 打包 + 发布
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
    [ValidateSet('Build', 'Analyze', 'Format', 'Test', 'Smoke', 'Pack', 'Release')]
    [string[]] $Task,
    [switch] $ResolveDependency = $true,
    [switch] $UseModuleFast = $true,
    [ValidateSet('major', 'minor', 'patch')]
    [string] $Bump,
    [switch] $Yes
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
    Format  = @()
    Test    = @('Build', 'Analyze')
    Smoke   = @()
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
    对 PSScriptAnalyzer 1.25.0 的已知偶发崩溃（PSUseCorrectCasing 空引用，
    上游 PowerShell/PSScriptAnalyzer#1708）做单文件有限重试，避免整批分析被随机打断。
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

    # 确保 PSScriptAnalyzer 已加载：显式导入可避开陈旧会话的模块缓存
    if (-not (Get-Command -Name 'Invoke-ScriptAnalyzer' -ErrorAction SilentlyContinue)) {
        [object]$analyzerModule = Get-Module -ListAvailable -Name 'PSScriptAnalyzer' |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
        if (-not $analyzerModule) {
            Write-Error '未找到 PSScriptAnalyzer。请先运行: Install-Module PSScriptAnalyzer -Scope CurrentUser -Force'
            exit 1
        }
        try {
            Import-Module -Name $analyzerModule.Path -Force -ErrorAction Stop
        }
        catch {
            Write-Error "PSScriptAnalyzer 导入失败: $($PSItem.Exception.Message)"
            exit 1
        }
    }

    # 收集待分析文件（排除 output/.git/node_modules/tests 和 build.ps1 本身）
    # 正则锚定到路径分隔符并转义点号，避免误伤文件名中含 output 等字样的源文件
    $excludedPathPattern = '[\\/](output|\.git|node_modules|tests)[\\/]'
    $analysisFiles = Get-ChildItem -Path $script:ModulePath -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
        Where-Object { $PSItem.FullName -notmatch $excludedPathPattern -and $PSItem.Name -ne 'build.ps1' }

    $settingsPath = Join-Path -Path $script:ModulePath -ChildPath 'PSScriptAnalyzerSettings.psd1'

    # 逐文件运行分析器
    # PSScriptAnalyzer 1.25.0 的 PSUseCorrectCasing 会对 CommandInfo.Parameters 空引用崩溃
    # （上游 PowerShell/PSScriptAnalyzer#1708，2021 年至今未修复，1.25.0 仍复现）。
    # 该崩溃属线程竞态：同一文件立即重跑通常即可恢复，故做有限重试；全部失败才上报并附文件名。
    $results = @()
    foreach ($File in $analysisFiles) {
        [int]$attempt = 0
        [bool]$analyzed = $false
        while (-not $analyzed -and $attempt -lt 3) {
            $attempt++
            try {
                $results += Invoke-ScriptAnalyzer -Path $File.FullName -Settings $settingsPath -ErrorAction Stop
                $analyzed = $true
            }
            catch {
                if ($attempt -ge 3) {
                    Write-Output "`n静态分析失败文件：$($File.FullName)"
                    Write-Output "最后一次异常：$($PSItem.Exception.Message)"
                    Write-Error '静态分析未通过'
                    exit 1
                }
                Write-Verbose "第 $attempt 次分析失败，重试：$($File.Name) - $($PSItem.Exception.Message)"
            }
        }
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

    # 解析失败与缺失声明分别收集：解析失败时 AST 不完整，继续检查只会得到假绿
    $parseFailures = @()
    $missing = @()
    foreach ($File in $auditFiles)
    {
        $tokens = $null
        $parseErrors = $null
        # 解析文件 AST 并查找全部函数定义
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$tokens, [ref]$parseErrors)

        # 语法错误时 ParseFile 仍会返回不完整的 AST，必须显式拦截，否则可能漏检函数
        if (@($parseErrors).Count -gt 0)
        {
            foreach ($ParseError in $parseErrors)
            {
                $parseFailures += [PSCustomObject]@{
                    File    = $File.Name
                    Line    = $ParseError.Extent.StartLineNumber
                    Message = $ParseError.Message
                }
            }
            continue
        }

        # -is 会匹配继承关系。由于 PowerShell 中类方法（class 内的 method）在 AST 中表示为 FunctionMemberAst，
        # 而非 FunctionDefinitionAst，因此此判断 天然排除了类方法，无需额外过滤。
        $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

        foreach ($Function in $functions)
        {
            # 提取 param 块 attribute 类型名；无 param 块时视为未声明 OutputType
            $attrNames = @(
                if ($null -ne $Function.Body.ParamBlock)
                {
                    $Function.Body.ParamBlock.Attributes | ForEach-Object { $PSItem.TypeName.Name }
                }
            )
            if (-not ($attrNames -contains 'OutputType'))
            {
                $missing += [PSCustomObject]@{
                    File     = $File.Name
                    Line     = $Function.Extent.StartLineNumber
                    Function = $Function.Name
                    Message  = '缺少 [OutputType()] 声明'
                }
            }
        }
    }

    # 解析失败优先报错：AST 不完整时无法确认契约，继续检查会得到假绿
    if ($parseFailures.Count -gt 0)
    {
        Write-Host ''
        Write-Host '以下文件存在语法错误，无法完成 OutputType 契约检查：'
        $parseFailures | Format-Table -Property File, Line, Message -AutoSize | Out-String -Stream | Write-Host
        Write-Error 'OutputType 契约检查未通过'
        exit 1
    }

    # 发现缺失则报错退出
    if ($missing.Count -gt 0)
    {
        Write-Host ''
        Write-Host '以下函数缺少 [OutputType()] 声明：'
        $missing | Format-Table -Property File, Line, Function, Message -AutoSize | Out-String -Stream | Write-Host
        Write-Error 'OutputType 契约检查未通过'
        exit 1
    }
    Write-Host 'OutputType 契约检查通过'
}

<#
.SYNOPSIS
    按 PSScriptAnalyzerSettings.psd1 格式化源码
.DESCRIPTION
    对 source/**/*.ps1 与 Main.ps1 运行 Invoke-Formatter，只回写内容有变化的文件。

    该 Task 独立于 Build/Analyze/Test：它会改写源码，与「构建可重复」相冲突，
    因此不进入任何依赖链，只在显式 -Task Format 时执行。

    两条安全约束：
    1. 混合行尾（既有 CRLF 又有孤立 LF）的文件列出后跳过，不猜用户想要哪种；
    2. 逐文件保留原有 BOM 状态与行尾，避免一次格式化把 15 个带 BOM 的文件悄悄改成无 BOM。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-FormatTask
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    Write-Output '格式化源码...'

    # 确保 PSScriptAnalyzer 已加载（Invoke-Formatter 由它提供）
    if (-not (Get-Command -Name 'Invoke-Formatter' -ErrorAction SilentlyContinue)) {
        try {
            Import-Module -Name 'PSScriptAnalyzer' -Force -ErrorAction Stop
        }
        catch {
            Write-Error "PSScriptAnalyzer 导入失败: $($PSItem.Exception.Message)"
            exit 1
        }
    }

    $settingsPath = Join-Path -Path $script:ModulePath -ChildPath 'PSScriptAnalyzerSettings.psd1'
    $formatFiles = @(Get-ChildItem -Path (Join-Path -Path $script:ModulePath -ChildPath 'source') -Recurse -Filter '*.ps1' -File) +
        @(Get-Item -Path (Join-Path -Path $script:ModulePath -ChildPath 'Main.ps1'))

    [int]$changedCount = 0
    [System.Collections.Generic.List[string]]$changed = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]]$skipped = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $formatFiles) {
        [byte[]]$bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        # BOM 状态必须逐文件保留：本仓库有 15 个文件带 BOM，统一抹掉会造成无关 diff
        [bool]$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        # ReadAllText 会自动剥离 BOM，得到不含 U+FEFF 的正文
        [string]$original = [System.IO.File]::ReadAllText($file.FullName)

        # 混合行尾：去掉 CRLF 后仍残留 LF，说明两种行尾并存
        [bool]$hasCrlf = $original.Contains("`r`n")
        [bool]$hasLoneLf = ($original -replace "`r`n", '').Contains("`n")
        if ($hasCrlf -and $hasLoneLf) {
            $skipped.Add($file.Name)
            continue
        }

        try {
            [string]$formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settingsPath -ErrorAction Stop
        }
        catch {
            Write-Error "格式化失败：$($file.FullName) - $($PSItem.Exception.Message)"
            exit 1
        }

        if ($formatted -ceq $original) {
            continue
        }

        # 行尾跟随原文件，避免格式化器改写整库行尾
        $formatted = $hasCrlf ? (($formatted -replace "`r`n", "`n") -replace "`n", "`r`n") : ($formatted -replace "`r`n", "`n")

        [System.IO.File]::WriteAllText($file.FullName, $formatted, [System.Text.UTF8Encoding]::new($hasBom))
        $changed.Add($file.Name)
        $changedCount++
    }

    if ($skipped.Count -gt 0) {
        Write-Output ''
        Write-Output '以下文件混合行尾，已跳过（请先统一为 LF 或 CRLF 再格式化）：'
        foreach ($name in $skipped) { Write-Output "  $name" }
    }

    Write-Output "格式化完成：改动 $changedCount 个文件，跳过 $($skipped.Count) 个"
    foreach ($name in $changed) { Write-Output "  已格式化：$name" }
}


<#
.SYNOPSIS
    Pester v5 测试 + 代码覆盖率
.DESCRIPTION
    运行 tests/ 目录下所有 *.Tests.ps1（单元 + 集成），启用 JaCoCo 代码覆盖率，
    输出 coverage.xml 到 output/。
    任何测试失败立即报错退出；测试通过后校验缺失行是否全部登记在 coverage-exemptions.psd1。
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

    # 覆盖率门禁：缺失行必须全部登记在 coverage-exemptions.psd1
    Test-CoverageExemption

    Write-Output "覆盖率报告：$coverageReportPath"
}

<#
.SYNOPSIS
    运行真实工具链冒烟
.DESCRIPTION
    只执行 tests/Manual 下的冒烟测试（真实 ffmpeg / Real-CUGAN，依赖 GPU）。
    与 Test task 的单元/集成测试分开，便于在本地快速复现或验收时单独触发。
    任何冒烟失败立即报错退出。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Invoke-SmokeTask
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    Write-Output '运行真实工具链冒烟...'

    $pesterConfig = New-PesterConfiguration -Hashtable @{
        Run = @{
            Path     = (Join-Path -Path $script:ModulePath -ChildPath 'tests\Manual')
            PassThru = $true
        }
    }

    $testResults = Invoke-Pester -Configuration $pesterConfig
    if ($testResults.FailedCount -gt 0)
    {
        Write-Error '冒烟未通过'
        exit 1
    }

    Write-Output '冒烟通过'
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
    校验覆盖率缺失行是否全部在豁免清单内
.DESCRIPTION
    读取 output/coverage.xml 与仓库根目录的 coverage-exemptions.psd1，做双向校验：
    1. coverage.xml 中任何未登记的缺失行 → 失败；
    2. 清单中已不再缺失的条目（已修复或行号漂移）→ 失败，强制同步清单。
    通过时输出「覆盖率豁免校验通过」。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Test-CoverageExemption
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    $coverageReportPath = Join-Path -Path $script:OutputPath -ChildPath 'coverage.xml'
    if (-not (Test-Path -LiteralPath $coverageReportPath))
    {
        Write-Error "覆盖率报告不存在：$coverageReportPath（请先运行 Test task）"
        exit 1
    }

    $exemptionPath = Join-Path -Path $script:ModulePath -ChildPath 'coverage-exemptions.psd1'
    if (-not (Test-Path -LiteralPath $exemptionPath))
    {
        Write-Error "覆盖率豁免清单不存在：$exemptionPath"
        exit 1
    }

    # 读取豁免清单：文件 → 行号集合
    $manifest = Import-PowerShellDataFile -LiteralPath $exemptionPath
    $registered = @{}
    foreach ($entry in $manifest.Exemptions)
    {
        $registered[[string]$entry.File] = @($entry.Lines | ForEach-Object { [int]$PSItem })
    }

    # 解析报告中的实际缺失行
    [xml]$coverageXml = Get-Content -LiteralPath $coverageReportPath -Raw -Encoding utf8
    $unregistered = @()
    $observed = @{}
    foreach ($sourceFile in $coverageXml.SelectNodes('//sourcefile'))
    {
        $name = [System.IO.Path]::GetFileName([string]$sourceFile.name)
        $missed = @($sourceFile.line |
            Where-Object { [int]$PSItem.mi -gt 0 -and [int]$PSItem.ci -eq 0 } |
            ForEach-Object { [int]$PSItem.nr })
        foreach ($line in $missed)
        {
            if (-not ($registered.ContainsKey($name) -and $registered[$name] -contains $line))
            {
                $unregistered += [PSCustomObject]@{ File = $name; Line = $line }
            }
            if (-not $observed.ContainsKey($name)) { $observed[$name] = @() }
            $observed[$name] += $line
        }
    }

    # 反向校验：清单里已不再缺失的条目视为过期
    $stale = @()
    foreach ($name in $registered.Keys)
    {
        foreach ($line in $registered[$name])
        {
            if (-not ($observed.ContainsKey($name) -and $observed[$name] -contains $line))
            {
                $stale += [PSCustomObject]@{ File = $name; Line = $line }
            }
        }
    }

    if ($unregistered.Count -gt 0)
    {
        Write-Host ''
        Write-Host '以下缺失行未在 coverage-exemptions.psd1 登记：'
        $unregistered | Format-Table -Property File, Line -AutoSize | Out-String -Stream | Write-Host
    }
    if ($stale.Count -gt 0)
    {
        Write-Host ''
        Write-Host '以下豁免条目已不再缺失（已修复或行号漂移），请同步更新清单：'
        $stale | Format-Table -Property File, Line -AutoSize | Out-String -Stream | Write-Host
    }
    if ($unregistered.Count -gt 0 -or $stale.Count -gt 0)
    {
        Write-Error '覆盖率豁免校验未通过'
        exit 1
    }

    Write-Host '覆盖率豁免校验通过'
}

<#
.SYNOPSIS
    严格校验字符串是否符合 SemVer 2.0.0
.DESCRIPTION
    使用 semver.org 官方正则校验。不能用 [semver]::TryParse 代替：
    实测它接受 01.2.3、1.2 等规范明确禁止的写法。
    预发布标识区分大小写，因此使用 -cmatch。
.PARAMETER Version
    待校验的版本字符串。
.OUTPUTS
    [bool]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Test-SemVerString
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Version
    )

    # semver.org 2.0.0 规范附录给出的官方正则
    $pattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'

    return $Version -cmatch $pattern
}

<#
.SYNOPSIS
    读取当前最高的版本 tag
.DESCRIPTION
    只认 v<semver> 形式的 tag，按版本号降序取第一个；没有可用 tag 时返回 $null。
.OUTPUTS
    [string] 形如 v1.0.0；无 tag 时返回 $null
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-LatestVersionTag
{
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    $tags = @(& git tag --list 'v*' --sort=-v:refname)
    foreach ($tag in $tags)
    {
        if (Test-SemVerString -Version $tag.Substring(1))
        {
            return $tag
        }
    }

    return $null
}

<#
.SYNOPSIS
    按 SemVer 规则计算下一个版本号
.DESCRIPTION
    major/minor/patch 分别推进对应位并把低位归零；输入只接受正式版（x.y.z）。
.PARAMETER BaseVersion
    基准版本（不带 v 前缀），如 1.2.3。
.PARAMETER Bump
    推进类型：major / minor / patch。
.OUTPUTS
    [string] 新版本号
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Get-BumpedVersion
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseVersion,
        [Parameter(Mandatory = $true)]
        [ValidateSet('major', 'minor', 'patch')]
        [string]$Bump
    )

    $parsed = [System.Management.Automation.SemanticVersion]::Parse($BaseVersion)
    switch ($Bump)
    {
        'major' { return "$($parsed.Major + 1).0.0" }
        'minor' { return "$($parsed.Major).$($parsed.Minor + 1).0" }
        default { return "$($parsed.Major).$($parsed.Minor).$($parsed.Patch + 1)" }
    }
}

<#
.SYNOPSIS
    把正式版版本号写回模块清单
.DESCRIPTION
    只替换 source/IPAP.psd1 的 ModuleVersion 字段，并清除已有的 Prerelease 标签
    （清单的 ModuleVersion 无法承载预发布后缀，预发布必须写在 PrivateData.PSData.Prerelease）。
    写回时保持原文件的 UTF-8 BOM 与 LF 行尾。
.PARAMETER Version
    正式版版本号（x.y.z）。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Set-ModuleVersion
{
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if ($Version -notmatch '^\d+\.\d+\.\d+$')
    {
        Write-Error "写回清单的版本必须是 Major.Minor.Patch（当前：$Version）"
        exit 1
    }

    $psd1Path = Join-Path -Path $script:SourcePath -ChildPath "$($script:ModuleName).psd1"
    [string]$content = Get-Content -LiteralPath $psd1Path -Raw -Encoding utf8
    # 去掉可能残留的 BOM 字符：Get-Content -Raw 会把它当普通字符读进来，
    # 写回时再补 BOM 就会叠加成多个 BOM，导致清单无法解析
    $content = $content.TrimStart([char]0xFEFF)
    [string]$updated = [regex]::Replace($content, "(?m)^(\s*ModuleVersion\s*=\s*)'[^']*'", "`${1}'$Version'")
    # 切正式版时清掉预发布标签，避免 1.2.0 与 1.2.0-beta.1 混用
    $updated = [regex]::Replace($updated, "(?m)^(\s*Prerelease\s*=\s*)'[^']*'\r?\n", '')

    if ($updated -eq $content -and $content -notmatch "ModuleVersion\s*=\s*'$([regex]::Escape($Version))'")
    {
        Write-Error '未在清单中找到可替换的 ModuleVersion'
        exit 1
    }

    # 保持 UTF-8 BOM（清单原有编码），只替换文本不碰行尾
    [System.IO.File]::WriteAllText($psd1Path, $updated, [System.Text.UTF8Encoding]::new($true))
}

<#
.SYNOPSIS
    读取 psd1 模块清单中的版本号（含预发布后缀）
.DESCRIPTION
    组合 ModuleVersion 与 PrivateData.PSData.Prerelease：
    清单字段只能写 x.y.z，因此 1.2.3-beta.1 会被还原成完整 SemVer 字符串。
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

    # 解析 psd1 内容：ModuleVersion 由 Loader 按 [version] 校验，这里补一层可读的失败信息
    $manifest = $null
    try
    {
        $manifest = Import-PowerShellDataFile -LiteralPath $psd1Path
    }
    catch
    {
        Write-Error "无法解析模块清单 $psd1Path：$($PSItem.Exception.Message)（ModuleVersion 需为 x.y.z，且不能有前导零）"
        exit 1
    }

    [string]$version = $manifest.ModuleVersion
    if ([string]::IsNullOrEmpty($version))
    {
        Write-Error 'psd1 中未找到 ModuleVersion'
        exit 1
    }

    [string]$prerelease = $manifest.PrivateData?.PSData?.Prerelease
    if (-not [string]::IsNullOrWhiteSpace($prerelease))
    {
        return "$version-$prerelease"
    }

    return $version
}

<#
.SYNOPSIS
    校验当前版本号可以用于打包/发布
.DESCRIPTION
    依次检查：符合 SemVer 2.0.0、对应 tag 尚未占用、高于最后一个版本 tag。
    在入口处执行，避免版本号有问题时还要先跑完 Build/Analyze/Test 才报错。
    远端 tag 由 Assert-RemoteTagFree 在发布前单独检查（Pack 不联网）。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Assert-VersionReady
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    [string]$version = Get-ModuleVersion
    if (-not (Test-SemVerString -Version $version))
    {
        Write-Error "版本号 '$version' 不符合 SemVer 2.0.0（示例：1.2.3、1.2.3-beta.1）"
        exit 1
    }

    [string]$tag = "v$version"
    $localTags = @(& git tag --list $tag)
    if ($localTags.Count -gt 0)
    {
        Write-Error "本地已存在 tag '$tag'（请用 -Bump 推进版本，或手工修改 ModuleVersion）"
        exit 1
    }

    [string]$latestTag = Get-LatestVersionTag
    if ($latestTag)
    {
        $latestVersion = [System.Management.Automation.SemanticVersion]::Parse($latestTag.Substring(1))
        $currentVersion = [System.Management.Automation.SemanticVersion]::Parse($version)
        if ($currentVersion -le $latestVersion)
        {
            Write-Error "版本 $version 必须大于最后一个 tag $latestTag（请用 -Bump 推进版本）"
            exit 1
        }
    }

    $latestText = $latestTag ? $latestTag : '无'
    Write-Output "版本校验通过：$version（最新 tag：$latestText）"
}

<#
.SYNOPSIS
    校验当前版本的 tag 在远端尚未存在
.DESCRIPTION
    发布前调用，避免重复发布同一版本。需要网络访问 origin。
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
function Assert-RemoteTagFree
{
    [CmdletBinding()]
    [OutputType([void])]
    param ()

    [string]$version = Get-ModuleVersion
    [string]$tag = "v$version"
    $remoteTags = @(& git ls-remote --tags origin "refs/tags/$tag" 2>$null)
    if ($remoteTags.Count -gt 0)
    {
        Write-Error "远端已存在 tag '$tag'（该版本已发布过）"
        exit 1
    }

    Write-Output "远端 tag 校验通过：$tag 尚未发布"
}

<#
.SYNOPSIS
    打包发布 zip
.DESCRIPTION
    组装发布暂存目录，包含：模块代码（IPAP/）、Main.ps1、运行时二进制（bin/）、
    config.toml.example、README.md（由 docs/QUICKSTART.md 生成）、RequiredModules/PSToml。
    最终压缩为 output/IPAP-v<Version>.zip。
    不生成 config.toml——首次运行时由 Main.ps1 从 config.toml.example 复制，
    这样升级解压不会覆盖用户已填的配置。

    前置校验：
    1. Build 产物存在（output/IPAP/）
    2. bin 下恰有一个 ffmpeg-*-shared 目录与一个 realcugan-* 目录
    3. docs/QUICKSTART.md 存在
    4. PSToml 已下载（output/RequiredModules/PSToml/）
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

    # 步骤 7：复制运行时二进制（ffmpeg shared 构建 + Real-CUGAN）
    # shared 构建必须连 DLL 一起复制，只带 exe 会启动失败
    $binSourceRoot = Join-Path -Path $script:ModulePath -ChildPath 'bin'
    $binRequirements = @(
        @{ Pattern = 'ffmpeg-*-shared'; Label = 'ffmpeg shared 构建' }
        @{ Pattern = 'realcugan-*'; Label = 'Real-CUGAN 与模型' }
    )
    $binDestRoot = Join-Path -Path $stagingPath -ChildPath 'bin'
    New-Item -ItemType Directory -Path $binDestRoot -Force | Out-Null
    $binDirNames = @{}
    foreach ($requirement in $binRequirements)
    {
        $matched = @(Get-ChildItem -Path $binSourceRoot -Directory -Filter $requirement.Pattern -ErrorAction SilentlyContinue)
        if ($matched.Count -ne 1)
        {
            Write-Error "bin 下应恰好有一个 $($requirement.Pattern) 目录（实际 $($matched.Count) 个）：$binSourceRoot"
            exit 1
        }
        Copy-Item -Path $matched[0].FullName -Destination $binDestRoot -Recurse -Force -ErrorAction Stop
        $binDirNames[$requirement.Pattern] = $matched[0].Name
    }

    # 步骤 8：复制配置模板（不直接生成 config.toml，避免升级覆盖用户已填的配置）
    $configSourcePath = Join-Path -Path $script:ModulePath -ChildPath 'config.toml.example'
    if (-not (Test-Path -LiteralPath $configSourcePath))
    {
        Write-Error "配置模板不存在：$configSourcePath"
        exit 1
    }
    # 把模板里的占位目录名替换成实际目录名，保证解压后配置里的路径即真实可用
    $configTemplate = Get-Content -LiteralPath $configSourcePath -Raw -Encoding utf8
    $configTemplate = $configTemplate.Replace('bin/ffmpeg-xxx/', "bin/$($binDirNames['ffmpeg-*-shared'])/")
    $configTemplate = $configTemplate.Replace('bin/realcugan-ncnn-vulkan-xxx/', "bin/$($binDirNames['realcugan-*'])/")
    $configDestPath = Join-Path -Path $stagingPath -ChildPath 'config.toml.example'
    Set-Content -LiteralPath $configDestPath -Value $configTemplate -Encoding utf8 -NoNewline

    # 步骤 9：复制快速开始文档为包内 README.md（仓库 .gitignore 忽略 **/README.md，故源文件叫 QUICKSTART.md）
    $quickStartSourcePath = Join-Path -Path $script:ModulePath -ChildPath 'docs\QUICKSTART.md'
    if (-not (Test-Path -LiteralPath $quickStartSourcePath))
    {
        Write-Error "快速开始文档不存在：$quickStartSourcePath"
        exit 1
    }
    Copy-Item -Path $quickStartSourcePath -Destination (Join-Path -Path $stagingPath -ChildPath 'README.md') -Force -ErrorAction Stop

    # 步骤 10：复制 RequiredModules/PSToml
    $pstomlSourcePath = Join-Path -Path $script:RequiredModulesPath -ChildPath 'PSToml'
    if (-not (Test-Path -LiteralPath $pstomlSourcePath))
    {
        Write-Error "PSToml 未下载：$pstomlSourcePath（请用 -ResolveDependency 运行）"
        exit 1
    }
    $pstomlDestPath = Join-Path -Path $stagingPath -ChildPath 'RequiredModules\PSToml'
    New-Item -ItemType Directory -Path (Split-Path -Path $pstomlDestPath -Parent) -Force | Out-Null
    Copy-Item -Path $pstomlSourcePath -Destination $pstomlDestPath -Recurse -Force -ErrorAction Stop

    # 步骤 11：压缩 zip
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

    # 步骤 1.1：发布前检查远端 tag，避免重复发布同一版本
    Assert-RemoteTagFree

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
    Write-Output '  1. git add .（暂存全部变更；无变更则跳过提交）'
    Write-Output "  2. git commit -m `"chore(release): v$version`""
    Write-Output "  3. git tag -a v$version -m 'Release v$version'"
    Write-Output "  4. git push origin $currentBranch --tags"
    Write-Output '  5. gh release create'
    Write-Output ''

    # 步骤 5：y/n 网关（不可逆操作前必须确认）
    if ($Yes)
    {
        Write-Output '已指定 -Yes，跳过交互确认'
    }
    else
    {
        $confirmation = Read-Host -Prompt '确认执行 commit + tag + push + gh release？(y/n)'
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y')
        {
            Write-Output '已中止发布。zip 保留在 output/ 目录。'
            return
        }
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

    # 提交：工作区干净时跳过，避免 "nothing to commit" 中断发布
    # （正常流程是先把代码提交好，再单独跑 Release 打 tag）
    $stagedFiles = @(& git diff --cached --name-only)
    if ($stagedFiles.Count -gt 0)
    {
        Write-Output '提交 commit...'
        $commitMessage = "chore(release): v$version 稳定发布"
        $null = & git commit -m $commitMessage
        if ($LASTEXITCODE -ne 0)
        {
            Write-Error 'git commit 失败'
            exit 1
        }
    }
    else
    {
        Write-Output '工作区无待提交变更，跳过 release commit，直接对当前 HEAD 打 tag'
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
        'Format' { Invoke-FormatTask }
        'Test' { Invoke-TestTask }
        'Smoke' { Invoke-SmokeTask }
        'Pack' { Invoke-PackTask }
        'Release' { Invoke-ReleaseTask }
    }

    # 标记为已执行
    $script:ExecutedTasks[$TaskName] = $true
}

# 入口：解析依赖 + 按 -Task 顺序执行
if ($Bump)
{
    if (-not ($Task -contains 'Pack' -or $Task -contains 'Release'))
    {
        Write-Error '-Bump 只能与 Pack 或 Release 一起使用（它会把新版本写回清单）'
        exit 1
    }

    [string]$latestTag = Get-LatestVersionTag
    if (-not $latestTag)
    {
        Write-Error '没有可用的版本 tag 作为基准，无法自动推进版本号'
        exit 1
    }

    [string]$baseVersion = $latestTag.Substring(1)
    [string]$newVersion = Get-BumpedVersion -BaseVersion $baseVersion -Bump $Bump
    Set-ModuleVersion -Version $newVersion
    Write-Output "版本号：$baseVersion -> $newVersion（-Bump $Bump）"
}

# 打包/发布前先校验版本号：格式、tag 未占用、高于最后一个版本 tag
if ($Task -contains 'Pack' -or $Task -contains 'Release')
{
    Assert-VersionReady
}

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
