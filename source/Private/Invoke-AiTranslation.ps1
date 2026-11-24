<#
.SYNOPSIS
    调用 OpenAI 兼容的 chat completions 接口翻译书名与简介
.DESCRIPTION
    一次请求同时产出中文译名与中文简介，返回严格 JSON 解析后的对象。
    只负责「发请求 + 解析」，不判断是否需要翻译、不改配置——那些由 Complete-ProjectTranslation 决定。

    请求特征：temperature = 0（同一输入稳定输出）、response_format = json_object（强制 JSON）、
    超时由调用方指定。任何失败（网络、超时、HTTP 错误、返回非 JSON、字段全空）
    都记 Warning 并返回 $null，由上层决定降级，绝不中断工作流。
.PARAMETER Endpoint
    chat completions 的完整地址，例如 https://api.deepseek.com/v1/chat/completions。
.PARAMETER Model
    模型名，例如 deepseek-chat。
.PARAMETER ApiKey
    API 密钥，随 Authorization: Bearer 头发送；不落盘。
.PARAMETER TimeoutSec
    单次请求超时（秒），默认 30。
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

        [AllowEmptyString()]
        [string]$OriginalTitle = '',

        [AllowEmptyString()]
        [string]$OriginalOverview = '',

        [bool]$NeedTitle = $true,

        [bool]$NeedOverview = $true
    )

    # 只要真正缺的字段，少给模型一点自由发挥的空间
    [string[]]$WantedKeys = @()
    if ($NeedTitle) {
        $WantedKeys += 'chinese_title：中文书名，保留原文里的 [作者] 前缀结构'
    }
    if ($NeedOverview) {
        $WantedKeys += 'chinese_overview：中文简介，逐段翻译，用空行保留原分段'
    }

    [string]$SystemPrompt = '你是日文漫画的中文译者。只输出一个 JSON 对象，不要解释，不要 Markdown 代码块。'
    [string]$UserPrompt = @"
把下面的日文资料翻译成简体中文，返回 JSON 对象，只包含这些键：
$($WantedKeys -join "`n")

【原文书名】
$OriginalTitle

【原文简介】
$OriginalOverview
"@

    [hashtable]$Payload = @{
        model           = $Model
        temperature     = 0
        max_tokens      = 4096
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
        Write-LogEntry -Level Warning -Message 'AI 翻译返回内容为空'
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

    [string]$ChineseTitle = $NeedTitle ? ([string]$Parsed.chinese_title).Trim() : ''
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
