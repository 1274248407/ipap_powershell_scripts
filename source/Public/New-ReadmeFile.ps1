<#
.SYNOPSIS
    创建 README.toml 项目记录文件
.DESCRIPTION
    根据项目配置与图片分级结果生成项目根目录的 README.toml。
    该文件同时承担两个职责：

    1. 项目记录（人看）：项目信息、张数、统一等级、异类页清单、进度与笔记
    2. 运行状态（程序读）：[run] 段的 status / project_level / realcugan_scale / model，
       用于判断上次是否跑完、以及参数变化后是否要全量重做

    重新生成时：[project] / [meta] / [run] / [summary] / [level] / [outliers] 全部按最新结果重写；
    手工维护的 [progress] / [notes] / [todo] / [misc] 从旧文件读回后原样保留，
    避免「跑一次笔记就被清空」。

    写出用模板拼装而不是 ConvertTo-Toml：后者会把嵌套表里的整数写成字符串、注释全部丢失。
    读取用 PSToml 的 ConvertFrom-Toml，见 Get-ReadmeToml。
    落盘前会用 ConvertFrom-Toml 再解析一遍自证——解析器与写入器是两套实现，
    模板拼装写错时当场失败，而不是留下一个读不回来的项目记录。

    创建失败时记录错误日志并抛出强类型异常。
.PARAMETER ProjectDir
    (string, Mandatory) 项目根目录路径。
.PARAMETER ProjectLevel
    (int, Mandatory) 项目统一等级（0/1/2），由 Get-ProjectLevel 归并得到。
.PARAMETER Status
    (string, Mandatory) 运行状态：running = 本次尚未收尾，done = 已通过校验。
.PARAMETER TextImageLevels
    (array) 有文字图的分级结果（可选），每个对象应包含 Image、Level、LongEdge、YDIF 属性。
.PARAMETER NonTextImageLevels
    (array) 无文字图的分级结果（可选），每个对象应包含 Image、Level、LongEdge、YDIF 属性。
.PARAMETER RealCuganScale
    (int) Real-CUGAN 的放大倍数，仅 Level 2 使用，默认 2。
.PARAMETER Author
    (string) 作者名，复制自 config.toml 的 [project].author。
.PARAMETER OriginalTitle
    (string) 原作品名（原文），复制自 config.toml 的 [project].original_title。
.PARAMETER ChineseTitle
    (string) 作品中文译名，复制自 config.toml 的 [project].chinese_title。
.PARAMETER OriginalOverview
    (string) 原文简介，复制自 config.toml 的 [project].original_overview。
.PARAMETER ChineseOverview
    (string) 中文简介，复制自 config.toml 的 [project].chinese_overview。
.PARAMETER ModelSelect
    (string) Real-CUGAN 模型名，写入 [run].model 用于参数变更检测。
.EXAMPLE
    New-ReadmeFile -ProjectDir 'C:\Projects\Manga1' -ProjectLevel 1 -Status 'running' -TextImageLevels $textLevels
    按 Level 1 生成 README.toml，并标记为运行中。
.EXAMPLE
    New-ReadmeFile -ProjectDir 'C:\Projects\Manga1' -ProjectLevel 0 -Status 'done' -TextImageLevels $t -NonTextImageLevels $nt
    校验通过后重写 README.toml，把 status 改为 done。
.INPUTS
    无
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function New-ReadmeFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2)]
        [int]$ProjectLevel,

        [Parameter(Mandatory = $true)]
        [ValidateSet('running', 'done')]
        [string]$Status,

        [AllowEmptyCollection()]
        [array]$TextImageLevels = @(),

        [AllowEmptyCollection()]
        [array]$NonTextImageLevels = @(),

        [ValidateRange(1, 4)]
        [int]$RealCuganScale = 2,

        [AllowEmptyString()]
        [string]$Author = '',

        [AllowEmptyString()]
        [string]$OriginalTitle = '',

        [AllowEmptyString()]
        [string]$ChineseTitle = '',

        [AllowEmptyString()]
        [string]$OriginalOverview = '',

        [AllowEmptyString()]
        [string]$ChineseOverview = '',

        [AllowEmptyString()]
        [string]$ModelSelect = ''
    )

    [string]$ReadmePath = Join-Path -Path $ProjectDir -ChildPath 'README.toml'

    if ($PSCmdlet.ShouldProcess($ReadmePath, '创建 README.toml 文件')) {
        [string]$Today = Get-Date -Format 'yyyy-MM-dd'

        # 全部派生量只在这里算一次，避免调用方与模板各写一份而互相矛盾
        [int]$TextCount = @($TextImageLevels).Count
        [int]$NonTextCount = @($NonTextImageLevels).Count
        [int]$TotalCount = $TextCount + $NonTextCount
        [string]$RatioText = switch ($ProjectLevel) {
            0 { '1.0' }
            1 { '1.2' }
            default { "$RealCuganScale.0" }
        }

        # 读取上一次的记录：既用于保留手工段落，也用于沿用同一次任务的开始时间
        [object]$Previous = Get-ReadmeToml -ProjectDir $ProjectDir
        [object]$PreviousRun = $Previous.run
        [string]$StartedAt = ([string]$PreviousRun.status -eq 'running' -and -not [string]::IsNullOrWhiteSpace([string]$PreviousRun.started_at)) `
            ? [string]$PreviousRun.started_at `
            : (Get-Date).ToString('o')

        # 手工维护的段落：旧文件有就照搬，没有就用默认值
        [object]$PreviousProgress = $Previous.progress
        [bool]$Organize = [bool]$PreviousProgress.organize
        [bool]$Ocr = [bool]$PreviousProgress.ocr
        [bool]$Inpainting = [bool]$PreviousProgress.inpainting
        [bool]$Translate = [bool]$PreviousProgress.translate
        [int]$TypesetPage = [int]$PreviousProgress.typeset_page
        [bool]$FinalCheck = [bool]$PreviousProgress.final_check

        [string]$NotesPreprocessing = [string]$Previous.notes.preprocessing
        [string]$NotesTranslate = [string]$Previous.notes.translate
        [string]$NotesTypeset = [string]$Previous.notes.typeset

        # @(... | Where-Object ...) 让「没有记录」「空数组」「有元素」三种情况都落到同一个 0..N 的结果
        [array]$TodoItems = @($Previous.todo.items | Where-Object { $null -ne $PSItem })
        [array]$MiscItems = @($Previous.misc.items | Where-Object { $null -ne $PSItem })

        [System.Text.StringBuilder]$Builder = [System.Text.StringBuilder]::new()

        [void]$Builder.AppendLine('# 项目记录（IPAP 自动生成）')
        [void]$Builder.AppendLine('# 重新运行会按最新分级结果重写 [meta] / [run] / [summary] / [level] / [outliers] 段；')
        [void]$Builder.AppendLine('# [project] 段复制自 config.toml；[progress] / [notes] / [todo] / [misc] 手工维护，重写时保留。')
        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('# ───────── 项目信息（最常看的一段，放在最上面）─────────')
        [void]$Builder.AppendLine('# 本节由 config.toml 的 [project] 复制而来，便于直接查看；')
        [void]$Builder.AppendLine('# 需要修改时请改 config.toml（项目目录名由 author + original_title 决定，两边不一致会混乱）')
        [void]$Builder.AppendLine('[project]')
        [void]$Builder.AppendLine('# 作者名')
        [void]$Builder.AppendLine("author = $(Format-TomlString -Value $Author)")
        [void]$Builder.AppendLine('# 原作品名（原文）')
        [void]$Builder.AppendLine("original_title = $(Format-TomlString -Value $OriginalTitle)")
        [void]$Builder.AppendLine('# 作品中文译名')
        [void]$Builder.AppendLine("chinese_title = $(Format-TomlString -Value $ChineseTitle)")
        [void]$Builder.AppendLine('# 原文简介（三引号包裹，换行原样保留）')
        [void]$Builder.AppendLine("original_overview = $(Format-TomlMultilineString -Value $OriginalOverview)")
        [void]$Builder.AppendLine('# 中文简介')
        [void]$Builder.AppendLine("chinese_overview = $(Format-TomlMultilineString -Value $ChineseOverview)")

        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('# ───────── 生成信息 ─────────')
        [void]$Builder.AppendLine('[meta]')
        [void]$Builder.AppendLine('format_version = 1')
        [void]$Builder.AppendLine("generated_at   = $(Format-TomlString -Value $Today)")

        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('# ───────── 运行状态（程序读，改它不会让流程重跑）─────────')
        [void]$Builder.AppendLine('# status = "running" → 上次没跑完，下次启动自动续跑；"done" → 已收尾')
        [void]$Builder.AppendLine('[run]')
        [void]$Builder.AppendLine("status          = $(Format-TomlString -Value $Status)")
        [void]$Builder.AppendLine("started_at      = $(Format-TomlString -Value $StartedAt)")
        [void]$Builder.AppendLine("project_level   = $ProjectLevel")
        [void]$Builder.AppendLine("realcugan_scale = $RealCuganScale")
        [void]$Builder.AppendLine("model           = $(Format-TomlString -Value $ModelSelect)")

        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('# ───────── 张数与统一等级 ─────────')
        [void]$Builder.AppendLine('[summary]')
        [void]$Builder.AppendLine("text_count     = $TextCount")
        [void]$Builder.AppendLine("non_text_count = $NonTextCount")
        [void]$Builder.AppendLine("total_count    = $TotalCount")
        [void]$Builder.AppendLine('# 1.0 = 不放大；1.2 = Level 1；2.0~4.0 = Level 2')
        [void]$Builder.AppendLine("upscale_ratio  = $RatioText")

        # 分级明细：每类只在有页面时输出，避免出现 count = 0 的空表
        if ($TextCount -gt 0) {
            [int[]]$TextEdges = @($TextImageLevels | ForEach-Object { [int]$PSItem.LongEdge })
            [double[]]$TextYdifs = @($TextImageLevels | ForEach-Object { [double]$PSItem.YDIF })
            [void]$Builder.AppendLine()
            [void]$Builder.AppendLine('[level.text]')
            [void]$Builder.AppendLine("count         = $TextCount")
            [void]$Builder.AppendLine("long_edge_min = $([int]($TextEdges | Measure-Object -Minimum).Minimum)")
            [void]$Builder.AppendLine("long_edge_max = $([int]($TextEdges | Measure-Object -Maximum).Maximum)")
            [void]$Builder.AppendLine("ydif_min      = $(Format-TomlNumber -Value ([double]($TextYdifs | Measure-Object -Minimum).Minimum))")
            [void]$Builder.AppendLine("ydif_max      = $(Format-TomlNumber -Value ([double]($TextYdifs | Measure-Object -Maximum).Maximum))")
        }

        if ($NonTextCount -gt 0) {
            [int[]]$NonTextEdges = @($NonTextImageLevels | ForEach-Object { [int]$PSItem.LongEdge })
            [double[]]$NonTextYdifs = @($NonTextImageLevels | ForEach-Object { [double]$PSItem.YDIF })
            [void]$Builder.AppendLine()
            [void]$Builder.AppendLine('[level.non_text]')
            [void]$Builder.AppendLine("count         = $NonTextCount")
            [void]$Builder.AppendLine("long_edge_min = $([int]($NonTextEdges | Measure-Object -Minimum).Minimum)")
            [void]$Builder.AppendLine("long_edge_max = $([int]($NonTextEdges | Measure-Object -Maximum).Maximum)")
            [void]$Builder.AppendLine("ydif_min      = $(Format-TomlNumber -Value ([double]($NonTextYdifs | Measure-Object -Minimum).Minimum))")
            [void]$Builder.AppendLine("ydif_max      = $(Format-TomlNumber -Value ([double]($NonTextYdifs | Measure-Object -Maximum).Maximum))")
        }

        # 异类页：单图等级与项目统一等级不同，需要人工复核「为什么没按它的等级处理」
        [array]$Outliers = @(
            foreach ($Level in @($TextImageLevels)) {
                if ([int]$Level.Level -ne $ProjectLevel) {
                    [PSCustomObject]@{ Level = $Level; Category = '有文字图' }
                }
            }
            foreach ($Level in @($NonTextImageLevels)) {
                if ([int]$Level.Level -ne $ProjectLevel) {
                    [PSCustomObject]@{ Level = $Level; Category = '无文字图' }
                }
            }
        )

        if ($Outliers.Count -gt 0) {
            [void]$Builder.AppendLine()
            [void]$Builder.AppendLine('# ───────── 与项目统一等级不一致的页面（需人工复核）─────────')
            foreach ($Outlier in $Outliers) {
                [void]$Builder.AppendLine()
                [void]$Builder.AppendLine('[[outliers]]')
                [void]$Builder.AppendLine("file      = $(Format-TomlString -Value ([System.IO.Path]::GetFileName($Outlier.Level.Image.FullName)))")
                [void]$Builder.AppendLine("category  = $(Format-TomlString -Value $Outlier.Category)")
                [void]$Builder.AppendLine("level     = $([int]$Outlier.Level.Level)")
                [void]$Builder.AppendLine("long_edge = $([int]$Outlier.Level.LongEdge)")
                [void]$Builder.AppendLine("ydif      = $(Format-TomlNumber -Value ([double]$Outlier.Level.YDIF))")
            }
        }

        # 以下四段手工维护：旧值原样搬回，保证重新运行不丢进度与笔记
        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('# ───────── 进度跟踪（手工维护，重新运行会保留）─────────')
        [void]$Builder.AppendLine('# 做完一步把 false 改成 true；嵌字进度写进 typeset_page')
        [void]$Builder.AppendLine('[progress]')
        [void]$Builder.AppendLine("organize     = $($Organize ? 'true' : 'false')")
        [void]$Builder.AppendLine("ocr          = $($Ocr ? 'true' : 'false')")
        [void]$Builder.AppendLine("inpainting   = $($Inpainting ? 'true' : 'false')")
        [void]$Builder.AppendLine("translate    = $($Translate ? 'true' : 'false')")
        [void]$Builder.AppendLine("typeset_page = $TypesetPage")
        [void]$Builder.AppendLine("final_check  = $($FinalCheck ? 'true' : 'false')")

        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('# ───────── 处理笔记（手工维护，重新运行会保留）─────────')
        [void]$Builder.AppendLine('[notes]')
        [void]$Builder.AppendLine("preprocessing = $(Format-TomlMultilineString -Value $NotesPreprocessing)")
        [void]$Builder.AppendLine("translate = $(Format-TomlMultilineString -Value $NotesTranslate)")
        [void]$Builder.AppendLine("typeset = $(Format-TomlMultilineString -Value $NotesTypeset)")

        [string[]]$TodoItemTexts = @($TodoItems | ForEach-Object { Format-TomlString -Value ([string]$PSItem) })
        [string[]]$MiscItemTexts = @($MiscItems | ForEach-Object { Format-TomlString -Value ([string]$PSItem) })

        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('# ───────── 待办 / 其他（手工维护，重新运行会保留）─────────')
        [void]$Builder.AppendLine('[todo]')
        [void]$Builder.AppendLine('# 每条一个字符串，例如 items = ["补第 12 页拟声词"]')
        [void]$Builder.AppendLine("items = [$($TodoItemTexts -join ', ')]")
        [void]$Builder.AppendLine()
        [void]$Builder.AppendLine('[misc]')
        [void]$Builder.AppendLine('# 任何你想记下的其他信息，每条一个字符串')
        [void]$Builder.AppendLine("items = [$($MiscItemTexts -join ', ')]")

        # 统一成 LF 行尾：构建过程混用了 AppendLine（CRLF），输出成一致的行尾便于 diff
        [string]$Content = $Builder.ToString() -replace "`r`n", "`n"

        # 落盘前用独立解析器自证：写入器是手写模板、解析器是 PSToml，两套实现互证。
        # 写错了就在这里失败，不给用户留下一个「能看不能读」的项目记录。
        if (Get-Command 'ConvertFrom-Toml' -ErrorAction SilentlyContinue) {
            try {
                $null = ConvertFrom-Toml -InputObject $Content -ErrorAction Stop
            }
            catch {
                # 记录错误现场后显式抛出强类型异常（Write-LogEntry 为纯日志函数）
                $ErrorMessage = "生成的 README.toml 无法被解析，已中止写入: $($PSItem.Exception.Message)"
                Write-LogEntry -Level Error -Message $ErrorMessage
                throw [System.InvalidOperationException]::new($ErrorMessage, $PSItem.Exception)
            }
        }

        try {
            Write-LogEntry -Level Info -Message "正在写入 README.toml 文件到 $ReadmePath"

            # 确保项目目录存在（使用 -LiteralPath 处理特殊字符）
            if (-not (Test-Path -LiteralPath $ProjectDir)) {
                # 记录错误现场后显式抛出强类型异常（Write-LogEntry 为纯日志函数）
                $ErrorMessage = "项目目录不存在: $ProjectDir"
                Write-LogEntry -Level Error -Message $ErrorMessage
                throw [System.ArgumentException]::new($ErrorMessage)
            }

            # 使用 Out-File -LiteralPath 写入文件，避免 PowerShell 通配符问题
            $Content | Out-File -LiteralPath $ReadmePath -Encoding utf8 -NoNewline

            if (Test-Path -LiteralPath $ReadmePath) {
                Write-LogEntry -Level Info -Message 'README.toml 文件创建/覆盖成功'
            }
            else {
                # 记录错误现场后显式抛出强类型异常（Write-LogEntry 为纯日志函数）
                $ErrorMessage = '无法验证 README.toml 文件创建'
                Write-LogEntry -Level Error -Message $ErrorMessage
                throw [System.InvalidOperationException]::new($ErrorMessage)
            }
        }
        catch {
            # 记录上下文后抛出包装异常并保留 InnerException（禁止吞异常）
            [string]$ErrorMessage = "创建/覆盖 README.toml 文件失败: $($PSItem.Exception.Message)"
            Write-LogEntry -Level Error -Message $ErrorMessage
            throw [System.IO.IOException]::new($ErrorMessage, $PSItem.Exception)
        }
    }
}
