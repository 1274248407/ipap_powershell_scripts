@{
    # 启用所有内置严重级别的规则（含 Error, Warning, Information 和 TBD）
    Severity     = @('Error', 'Warning', 'Information', 'TBD')
    # 排除 BOM 规则：pwsh7 默认 UTF8-noBOM，项目规则禁止依赖 BOM 行为
    ExcludeRules = @('PSUseBOMForUnicodeEncodedFile')

    # 格式化规则：PSScriptAnalyzer 默认不执行，必须显式 Enable。
    # 花括号采用 K&R（One True Brace Style）：Microsoft Learn 的 PlaceOpenBrace.OnSameLine
    # 默认值即 $true，PoshCode《PowerShell Practice and Style》亦推荐此写法，
    # 且与本仓库 tests/ 下测试文件的既有风格一致。
    # PSUseConsistentWhitespace.CheckOperator 关闭：该子项要求运算符两侧恰好一个空格，
    # 与刻意对齐的哈希表 / 模块清单相冲突（实测 25 处违规全部来自对齐填充，
    # 无一例真实运算符空格错误）。其余子项保留。
    Rules        = @{
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }
        PSUseConsistentWhitespace  = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $false
            CheckSeparator  = $true
            CheckParameter  = $true
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
        PSUseCorrectCasing         = @{
            Enable = $true
        }
    }
}