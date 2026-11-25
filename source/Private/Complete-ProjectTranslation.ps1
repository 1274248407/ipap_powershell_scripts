<#
.SYNOPSIS
    中文译名/简介缺失时用 AI 补全（仅本次运行生效）
.DESCRIPTION
    在配置预览之前调用，按需补全 config 里的两项中文字段：

    1. 未配置 `[ai].endpoint` 或未设置密钥环境变量 → 记一行 Info 后直接返回（这是默认状态）
    2. 中文译名/简介任意一项「缺失」→ 调一次 AI，把结果写回内存中的配置对象
       缺失的判定见 Test-NeedsTranslation：空 / 占位文本 / 等于原文 / 不是中文
    3. 原文为空 → 无法翻译，记 Warning 后返回
    4. 任何失败 → 记 Warning、保持原值，绝不中断工作流

    **不写回 config.toml**：配置文件是用户手写的，写回会破坏注释与格式；
    补全结果只改内存对象，因此预览与 README 都能看到，下次运行若仍缺会重新补。
.PARAMETER Config
    已初始化的配置实例（会被就地修改）。
.EXAMPLE
    Complete-ProjectTranslation -Config $config
    按需要补全 $config.Project.ChineseTitle 与 ChineseOverview。
.INPUTS
    无
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Complete-ProjectTranslation {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [IPAPConfiguration]$Config
    )

    if ([string]::IsNullOrWhiteSpace($Config.App.AiEndpoint)) {
        Write-LogEntry -Level Info -Message 'config.toml 未配置 [ai].endpoint，跳过 AI 补全'
        return
    }

    if ([string]::IsNullOrWhiteSpace($Config.App.AiModel)) {
        Write-LogEntry -Level Warning -Message 'config.toml 配置了 [ai].endpoint 但 [ai].model 为空，跳过 AI 补全'
        return
    }

    # 密钥优先级：环境变量 > 配置文件 [ai].api_key；两者都不记进日志
    [string]$ApiKey = ''
    if (-not [string]::IsNullOrWhiteSpace($Config.App.AiApiKeyEnv)) {
        $ApiKey = [string][Environment]::GetEnvironmentVariable($Config.App.AiApiKeyEnv)
    }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        $ApiKey = [string]$Config.App.AiApiKey
    }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-LogEntry -Level Info -Message "未找到 AI 密钥（环境变量 $($Config.App.AiApiKeyEnv) 与 [ai].api_key 均为空），跳过 AI 补全"
        return
    }

    # 占位文本从随包的 config.toml.example 实时读取：改示例就自动跟随，不在代码里硬编码文案
    [object]$Example = $null
    [string]$ExamplePath = Join-Path -Path $Config.Paths.ProjectRoot -ChildPath 'config.toml.example'
    if (Test-Path -LiteralPath $ExamplePath -PathType Leaf) {
        try {
            [string]$ExampleText = Get-Content -LiteralPath $ExamplePath -Raw -Encoding utf8 -ErrorAction Stop
            $Example = ConvertFrom-Toml -InputObject $ExampleText -ErrorAction Stop
        }
        catch {
            # 示例文件读不出来只影响占位符判定，降级为「只判空 / 只判原文相同」
            Write-LogEntry -Level Warning -Message "config.toml.example 读取失败，占位符判定降级: $($PSItem.Exception.Message)"
        }
    }

    [bool]$NeedTitle = Test-NeedsTranslation -Value $Config.Project.ChineseTitle `
        -Placeholder ([string]$Example.project.chinese_title) `
        -Original $Config.Project.OriginalTitle
    [bool]$NeedOverview = Test-NeedsTranslation -Value $Config.Project.ChineseOverview `
        -Placeholder ([string]$Example.project.chinese_overview) `
        -Original $Config.Project.OriginalOverview

    if (-not ($NeedTitle -or $NeedOverview)) {
        Write-LogEntry -Level Info -Message '中文译名与简介均已填写，跳过 AI 补全'
        return
    }

    if ([string]::IsNullOrWhiteSpace($Config.Project.OriginalTitle) -and
        [string]::IsNullOrWhiteSpace($Config.Project.OriginalOverview)) {
        Write-LogEntry -Level Warning -Message '原文书名与原文简介都为空，无从补全中文，请先在 config.toml 填写原文'
        return
    }

    [string[]]$MissingFields = @()
    if ($NeedTitle) { $MissingFields += '中文译名' }
    if ($NeedOverview) { $MissingFields += '中文简介' }
    Write-LogEntry -Level Info -Message "AI 补全待处理字段: $($MissingFields -join '、')"

    [object]$Result = Invoke-AiTranslation -Endpoint $Config.App.AiEndpoint -Model $Config.App.AiModel `
        -ApiKey $ApiKey -TimeoutSec $Config.App.AiTimeoutSec -Temperature $Config.App.AiTemperature `
        -MaxTokens $Config.App.AiMaxTokens -ReasoningEffort $Config.App.AiReasoningEffort `
        -OriginalTitle $Config.Project.OriginalTitle `
        -OriginalOverview $Config.Project.OriginalOverview `
        -NeedTitle $NeedTitle -NeedOverview $NeedOverview

    if ($null -eq $Result) {
        Write-LogEntry -Level Warning -Message 'AI 补全未成功，保持原值继续（未写回 config.toml）'
        return
    }

    if ($NeedTitle -and -not [string]::IsNullOrWhiteSpace($Result.ChineseTitle)) {
        $Config.Project.ChineseTitle = $Result.ChineseTitle
        Write-LogEntry -Level Success -Message "AI 补全中文译名: $($Result.ChineseTitle)"
    }

    if ($NeedOverview -and -not [string]::IsNullOrWhiteSpace($Result.ChineseOverview)) {
        $Config.Project.ChineseOverview = $Result.ChineseOverview
        Write-LogEntry -Level Success -Message 'AI 补全中文简介（仅本次运行生效，未写回 config.toml）'
    }
}
