<#
.SYNOPSIS
    调用 OpenAI 兼容的 chat completions 接口翻译书名与简介
.DESCRIPTION
    一次请求同时产出中文译名与中文简介，返回严格 JSON 解析后的对象。
    只负责「发请求 + 解析」，不判断是否需要翻译、不改配置——那些由 Complete-ProjectTranslation 决定。

    请求特征：temperature 来自 `[ai].temperature`（默认 0，同一输入稳定输出）、
    response_format = json_object（强制 JSON）、超时由调用方指定。
    任何失败（网络、超时、HTTP 错误、返回非 JSON、字段全空）
    都记 Warning 并返回 $null，由上层决定降级，绝不中断工作流。

    **方括号里的作者名不送进模型**：`[作者] 正文` 先拆两段，只翻译正文，返回后原样拼回前缀。
    作者名是专有名词，靠提示词要求「保留」并不可靠，直接不让它进入请求才是最硬的保证。
.PARAMETER Endpoint
    chat completions 的完整地址，例如 https://api.deepseek.com/v1/chat/completions。
.PARAMETER Model
    模型名，例如 deepseek-chat。
.PARAMETER ApiKey
    API 密钥，随 Authorization: Bearer 头发送；不落盘。
.PARAMETER TimeoutSec
    单次请求超时（秒），默认 30。
.PARAMETER Temperature
    采样温度，来自 `[ai].temperature`；0 表示同一输入稳定输出，取值范围 0-2。
.PARAMETER MaxTokens
    单次回复的最大 token 数，来自 `[ai].max_tokens`；推理模型会把思考内容也算进这个额度。
.PARAMETER OriginalTitle
    原文书名。
.PARAMETER OriginalOverview
    原文简介。
.PARAMETER NeedTitle
    是否请求中文译名；$false 时该字段固定返回空串。
.PARAMETER NeedOverview
    是否请求中文简介；$false 时该字段固定返回空串。
.EXAMPLE
    Invoke-AiTranslation -Endpoint 'https://api.deepseek.com/v1/chat/completions' -Model 'deepseek-chat' -ApiKey $key -OriginalTitle '僕の妻' -OriginalOverview 'あらすじ'
    返回 @{ ChineseTitle = '...'; ChineseOverview = '...' }。
.INPUTS
    无
.OUTPUTS
    PSCustomObject（含 ChineseTitle / ChineseOverview 两个字符串属性）；失败时返回 $null
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Invoke-AiTranslation {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [string]$ApiKey,

        [ValidateRange(1, 600)]
        [int]$TimeoutSec = 30,

        [ValidateRange(0, 2)]
        [double]$Temperature = 0,

        [ValidateRange(256, 65536)]
        [int]$MaxTokens = 8192,

        [AllowEmptyString()]
        [string]$OriginalTitle = '',

        [AllowEmptyString()]
        [string]$OriginalOverview = '',

        [bool]$NeedTitle = $true,

        [bool]$NeedOverview = $true
    )

    # 方括号里的作者名是专有名词，不送进模型：只翻译正文，返回后再原样拼回
    [object]$TitleParts = Split-AuthorPrefix -Title $OriginalTitle
    [bool]$TranslateTitle = $NeedTitle -and -not [string]::IsNullOrWhiteSpace($TitleParts.Body)

    # 只要真正缺的字段，少给模型一点自由发挥的空间
    [string[]]$WantedKeys = @()
    if ($TranslateTitle) {
        $WantedKeys += 'chinese_title：中文书名正文（不要包含作者名，也不要加方括号）'
    }
    if ($NeedOverview) {
        $WantedKeys += 'chinese_overview：中文简介，逐段翻译，用空行保留原分段'
    }

    [string]$SystemPrompt = @'
你作为我的专业文学翻译助手，需要将日语精准翻译为简体中文。请严格遵循以下要求执行翻译工作：

**核心原则：**
在绝对保留原文格式与符号的前提下，确保译文准确传达原文信息。

**具体指令：**
1.  **格式绝对保留（最高优先级）**：
    - 严格逐行翻译，完全保留所有格式元素，包括：序号、标记符、占位符、换行符、缩进、转义符以及任何代码或特殊调用。
    - **严禁以任何理由合并或拆分原始行，或改变原始排版结构。**

2.  **精准性保障与修正原则**：
    - 确保原文含义的完整、准确传递，任何情况下均以字面准确性为最高优先，不得以牺牲准确性为代价追求文采。
    - 仅当发现原文存在明显拼写错误时，允许进行最小程度的修正，且修正后必须保持最大程度的原文忠实度。**不涉及语法调整或其他类型修正。**

3.  **输出规范**：
    - 只输出最终译文
    - 不包含任何额外的解释、说明或注释。

**机器可读的输出形式（覆盖上面第 3 条的「只输出译文」）：**
本次结果由程序直接解析，最终回复必须是一个 JSON 对象，不要 Markdown 代码块，不要任何前后缀：
{"chinese_title": "书名译文", "chinese_overview": "简介译文"}
- chinese_title：只放书名正文，不要带作者名、不要加方括号
- chinese_overview：简介译文，原分段用 \n 表示
'@
    [string]$UserPrompt = @"
把下面的日文资料翻译成简体中文，返回 JSON 对象，只包含这些键：
$($WantedKeys -join "`n")

【原文书名】
$($TitleParts.Body)

【原文简介】
$OriginalOverview
"@

    [hashtable]$Payload = @{
        model           = $Model
        temperature     = $Temperature
        max_tokens      = $MaxTokens
        response_format = @{ type = 'json_object' }
        messages        = @(
            @{ role = 'system'; content = $SystemPrompt }
            @{ role = 'user'; content = $UserPrompt }
        )
    }
    # 显式转成 UTF-8 字节，避免中文在请求体里被按本地代码页编码
    [byte[]]$Body = [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Depth 8))

    try {
        $Response = Invoke-RestMethod -Uri $Endpoint -Method Post -Body $Body `
            -ContentType 'application/json; charset=utf-8' `
            -Headers @{ Authorization = "Bearer $ApiKey" } `
            -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
    catch {
        # 网络/鉴权/超时都在这里：记录原因后交给上层降级
        Write-LogEntry -Level Warning -Message "AI 翻译请求失败: $($PSItem.Exception.Message)"
        return $null
    }

    [string]$RawContent = [string]$Response.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($RawContent)) {
        # 推理模型会把思考过程也算进 max_tokens：额度耗尽时 content 为空、finish_reason 为 length，
        # 此时只说「返回内容为空」会让人误以为是网络问题，必须指出真正原因
        [string]$FinishReason = [string]$Response.choices[0].finish_reason
        [int]$CompletionTokens = [int]($Response.usage.completion_tokens ?? 0)
        [bool]$HasReasoning = -not [string]::IsNullOrWhiteSpace([string]$Response.choices[0].message.reasoning_content)
        if ($FinishReason -eq 'length') {
            Write-LogEntry -Level Warning -Message ("AI 输出被 max_tokens 截断（completion={0}，含思考内容={1}）；请调大 [ai].max_tokens，或改用非推理模型" -f $CompletionTokens, $HasReasoning)
        }
        else {
            Write-LogEntry -Level Warning -Message 'AI 翻译返回内容为空'
        }
        return $null
    }

    $Parsed = $null
    try {
        $Parsed = $RawContent | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-LogEntry -Level Warning -Message "AI 翻译返回的不是合法 JSON: $($PSItem.Exception.Message)"
        return $null
    }

    [string]$TranslatedTitleBody = $TranslateTitle ? ([string]$Parsed.chinese_title).Trim() : ''
    # 拼回作者前缀：模型只见过正文，作者名一个字符都没经过它
    [string]$ChineseTitle = ''
    if ($TranslatedTitleBody) {
        $ChineseTitle = $TitleParts.Prefix ? "$($TitleParts.Prefix) $TranslatedTitleBody" : $TranslatedTitleBody
    }
    [string]$ChineseOverview = $NeedOverview ? ([string]$Parsed.chinese_overview).Trim() : ''

    if ([string]::IsNullOrWhiteSpace($ChineseTitle) -and [string]::IsNullOrWhiteSpace($ChineseOverview)) {
        Write-LogEntry -Level Warning -Message 'AI 翻译未返回可用的中文内容'
        return $null
    }

    return [PSCustomObject]@{
        ChineseTitle    = $ChineseTitle
        ChineseOverview = $ChineseOverview
    }
}
