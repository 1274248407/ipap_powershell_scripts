<#
.SYNOPSIS
        创建项目目录结构
.DESCRIPTION
        创建符合 IPAP 工作流标准的项目目录结构，包括预处理和排版目录。
        若目录已存在则询问用户是否覆盖，创建失败时记录错误日志。
        BaseDir 与 ProjectName 在函数入口做空白与尾点校验，非法入参记录 Error 日志后抛出
        [System.ArgumentException]，不创建任何目录。
        在项目目录下创建子目录：
        '02_Preprocessing\raw_source',
        '02_Preprocessing\original_non_text_raw',
        '02_Preprocessing\inpainted',
        '02_Preprocessing\mask',
        '03_Typesetting\workfiles',
        '03_Typesetting\final_pages'
.PARAMETER BaseDir
        (string) 项目基础目录路径。
        不能为纯空白字符串，也不能以 ASCII 空白字符（0x20/0x09/0x0A/0x0B/0x0C/0x0D）或点 (.) 结尾，
        否则抛出 [System.ArgumentException]（Win32 路径规范化会裁剪路径末段的此类字符，
        使同一入参同时产出裁剪空壳与真身两个目录，真实产物落入不可寻址路径，即目录分裂）。
.PARAMETER ProjectName
        (string) 项目名称。
        同样受上述空白与尾点约束：不能为纯空白字符串，不能以 ASCII 空白字符或点 (.) 结尾。
.PARAMETER Force
    (switch) 跳过确认提示，直接覆盖已存在的目录。
.EXAMPLE
        New-ProjectStructure -BaseDir "C:\Projects" -ProjectName "Manga1"
        在 C:\Projects 目录下创建名为 2026-04-20_Manga1 的项目目录。
.INPUTS
        无
.OUTPUTS
        string 或 $null (创建成功时返回项目目录路径)
.NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
#>

function New-ProjectStructure {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseDir,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,
        [switch]$Force
    )

    # 参数空白与尾点守卫（目录分裂防线）：
    # Win32 路径规范化会裁剪路径末段的 ASCII 空白与尾部点，而中间段的同类字符会被保留，
    # 同一入参会因此产出「裁剪空壳」与「真身」两个目录，真实产物落入 provider 无法寻址的路径。
    # 判据按探针实证精确设定：ASCII 空白与尾点会触发裁剪；NBSP(U+00A0)、全角空格(U+3000)
    # 实测既不被裁剪也可正常寻址，故不拒绝（放行，不为无害入参报错）。
    $AsciiWhitespace = [char[]]@([char]0x20, [char]0x09, [char]0x0A, [char]0x0B, [char]0x0C, [char]0x0D)

    if ([string]::IsNullOrWhiteSpace($BaseDir)) {
        $ErrorMessage = "参数 'BaseDir' 不能为纯空白字符串（当前值: '$BaseDir'）"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    if ($BaseDir -ne $BaseDir.Trim($AsciiWhitespace)) {
        $ErrorMessage = "参数 'BaseDir' 不能以空白字符开头或结尾（当前值: '$BaseDir'）"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    if ($BaseDir.EndsWith('.')) {
        $ErrorMessage = "参数 'BaseDir' 不能以点 (.) 结尾（当前值: '$BaseDir'）"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ErrorMessage = "参数 'ProjectName' 不能为纯空白字符串（当前值: '$ProjectName'）"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    if ($ProjectName -ne $ProjectName.Trim($AsciiWhitespace)) {
        $ErrorMessage = "参数 'ProjectName' 不能以空白字符开头或结尾（当前值: '$ProjectName'）"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    if ($ProjectName.EndsWith('.')) {
        $ErrorMessage = "参数 'ProjectName' 不能以点 (.) 结尾（当前值: '$ProjectName'）"
        Write-LogEntry -Level Error -Message $ErrorMessage
        throw [System.ArgumentException]::new($ErrorMessage)
    }

    # 构建项目目录路径
    $today = Get-Date -Format 'yyyy-MM-dd'
    $projectDirName = "${today}_${ProjectName}"
    $projectDir = Join-Path -Path $BaseDir -ChildPath $projectDirName

    # 闸门顺序：必须先过 ShouldProcess，再进入覆盖确认。
    # SupportsShouldProcess 的契约是 WhatIf 零副作用且零交互；旧实现把确认放在闸门之前，
    # 导致 -WhatIf 仍会调用交互方法，实测抛出 MethodInvocationException（内含 NullReferenceException）。
    if ($PSCmdlet.ShouldProcess($projectDir, '创建项目目录结构')) {
        # 使用 -LiteralPath 处理包含特殊字符的路径
        # 覆盖确认：使用 Read-Host 而非 $PSCmdlet.ShouldContinue。
        # ShouldContinue 是 PSCmdlet 的方法而非命令，而 Pester 只能 Mock 命令，无法拦截方法调用，
        # 会使本分支在单元测试中永远不可达；Read-Host 是系统命令，可被 Mock。
        if ((Test-Path -LiteralPath $projectDir) -and (-not $Force)) {
            # 安全默认：仅显式 Y/y 视为覆盖；回车、EOF（Read-Host 返回 $null）与
            # 其它任何输入一律视为取消，避免非交互环境下的死循环与误覆盖
            $Response = Read-Host '项目目录已存在，是否覆盖现有目录？(Y/N)'
            if (([string]$Response).Trim() -notin @('Y', 'y')) {
                Write-LogEntry -Level Info -Message '用户取消覆盖操作'
                return $null
            }
        }

        try {
            Write-LogEntry -Level Info -Message "正在创建项目目录: $projectDir"

            New-Item -ItemType Directory -Path $projectDir -Force | Out-Null

            $subDirs = @(
                '02_Preprocessing\raw_source',
                '02_Preprocessing\original_non_text_raw',
                '02_Preprocessing\inpainted',
                '02_Preprocessing\mask',
                '03_Typesetting\workfiles',
                '03_Typesetting\final_pages'
            )

            foreach ($subDir in $subDirs) {
                $fullPath = Join-Path $projectDir $subDir
                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                Write-LogEntry -Level Info -Message "已创建子目录: $fullPath"
            }

            Write-LogEntry -Level Info -Message '项目目录结构创建成功'
            return $projectDir
        }
        catch {
            # 记录错误信息后抛出包装异常（禁止吞异常）
            $errorMessage = "创建项目目录失败: $($PSItem.Exception.Message)"
            Write-LogEntry -Level Error -Message $errorMessage
            throw [System.IO.IOException]::new($errorMessage, $PSItem.Exception)
        }
    }
}
