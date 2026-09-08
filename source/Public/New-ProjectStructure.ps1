<#
.SYNOPSIS
        创建项目目录结构
.DESCRIPTION
        创建符合 IPAP 工作流标准的项目目录结构，包括预处理和排版目录。
        若目录已存在则询问用户是否覆盖，创建失败时记录错误日志。
        在项目目录下创建子目录：
        '02_Preprocessing\raw_source',
        '02_Preprocessing\original_non_text_raw',
        '02_Preprocessing\inpainted',
        '02_Preprocessing\mask',
        '03_Typesetting\workfiles',
        '03_Typesetting\final_pages'
.PARAMETER BaseDir
        (string) 项目基础目录路径。
.PARAMETER ProjectName
        (string) 项目名称。
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

function New-ProjectStructure
{
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseDir,
        [Parameter(Mandatory = $true)]
        [string]$ProjectName,
        [switch]$Force
    )

    # 构建项目目录路径
    $today = Get-Date -Format 'yyyy-MM-dd'
    $projectDirName = "${today}_${ProjectName}"
    $projectDir = Join-Path -Path $BaseDir -ChildPath $projectDirName

    # 使用 -LiteralPath 处理包含特殊字符的路径
    if (Test-Path -LiteralPath $projectDir)
    {
        # 当 -Force 指定时跳过确认提示
        if (-not $Force -and -not $PSCmdlet.ShouldContinue('项目目录已存在，是否覆盖现有目录？', '确认操作'))
        {
            Write-LogEntry -Level Info -Message '用户取消覆盖操作'
            return $null
        }
    }

    if ($PSCmdlet.ShouldProcess($projectDir, '创建项目目录结构'))
    {
        try
        {
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

            foreach ($subDir in $subDirs)
            {
                $fullPath = Join-Path $projectDir $subDir
                New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
                Write-LogEntry -Level Info -Message "已创建子目录: $fullPath"
            }

            Write-LogEntry -Level Info -Message '项目目录结构创建成功'
            return $projectDir
        }
        catch
        {
            # 记录错误信息后抛出包装异常（禁止吞异常）
            $errorMessage = "创建项目目录失败: $($PSItem.Exception.Message)"
            Write-LogEntry -Level Error -Message $errorMessage
            throw [System.IO.IOException]::new($errorMessage, $PSItem.Exception)
        }
    }
}
