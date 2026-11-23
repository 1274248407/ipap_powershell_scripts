<#
.SYNOPSIS
    读取项目根目录的 README.toml
.DESCRIPTION
    README.toml 同时承担两件事：项目记录（人看）与运行状态（程序读）。
    本函数负责读那份文件，供两个用途共用：
    1. 判断上次运行是否跑完（[run].status）
    2. 取回手工维护的段落（[progress] / [notes] / [todo] / [misc]），重新生成时原样保留

    文件不存在、内容为空或解析失败时一律按「没有记录」返回 $null，不让一个坏文件卡住流程。
    解析失败时会把坏文件改名为 README.toml.bad 留证据，避免用户的笔记被静默覆盖。
.PARAMETER ProjectDir
    项目根目录。
.EXAMPLE
    $Readme = Get-ReadmeToml -ProjectDir 'C:\Projects\2026-11-22_某项目'
    $Readme.run.status
.INPUTS
    无
.OUTPUTS
    System.Collections.Specialized.OrderedDictionary（TOML 解析结果）；无记录时返回 $null
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Get-ReadmeToml {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir
    )

    [string]$ReadmePath = Join-Path -Path $ProjectDir -ChildPath 'README.toml'
    if (-not (Test-Path -LiteralPath $ReadmePath -PathType Leaf)) {
        return $null
    }

    # 未加载过配置时 PSToml 可能还不在会话里（例如直接调用 New-ReadmeFile），按与配置加载一致的候选顺序兜底导入
    if (-not (Get-Command 'ConvertFrom-Toml' -ErrorAction SilentlyContinue)) {
        [string]$ModuleRoot = Split-Path -Path $PSScriptRoot -Parent
        foreach ($Candidate in @(
                (Join-Path -Path $ModuleRoot -ChildPath 'RequiredModules\PSToml'),
                (Join-Path -Path (Split-Path -Path $ModuleRoot -Parent) -ChildPath 'output\RequiredModules\PSToml')
            )) {
            if (-not (Test-Path -LiteralPath $Candidate)) {
                continue
            }
            try {
                Import-Module $Candidate -Force -Scope Global -ErrorAction Stop
                break
            }
            catch {
                Write-LogEntry -Level Warning -Message "PSToml 模块导入失败，跳过候选路径: $Candidate"
            }
        }
    }

    if (-not (Get-Command 'ConvertFrom-Toml' -ErrorAction SilentlyContinue)) {
        Write-LogEntry -Level Warning -Message 'PSToml 模块不可用，README.toml 按「无记录」处理'
        return $null
    }

    try {
        [string]$RawToml = Get-Content -LiteralPath $ReadmePath -Raw -Encoding utf8 -ErrorAction Stop
    }
    catch {
        # 读文件属 IO 边界：记日志后按「无记录」处理，后续会整份重写
        Write-LogEntry -Level Warning -Message "README.toml 读取失败，按无记录处理: $($PSItem.Exception.Message)"
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($RawToml)) {
        return $null
    }

    try {
        return (ConvertFrom-Toml -InputObject $RawToml -ErrorAction Stop)
    }
    catch {
        # 先把坏文件改名留证据，再按无记录处理：用户的笔记即便读不出来也不该被直接覆盖掉
        [string]$BrokenPath = "$ReadmePath.bad"
        try {
            Move-Item -LiteralPath $ReadmePath -Destination $BrokenPath -Force -ErrorAction Stop
            Write-LogEntry -Level Error -Message "README.toml 解析失败（已备份为 $BrokenPath），本次按全量重做: $($PSItem.Exception.Message)"
        }
        catch {
            Write-LogEntry -Level Error -Message "README.toml 解析失败且备份失败，本次按全量重做: $($PSItem.Exception.Message)"
        }
        return $null
    }
}
