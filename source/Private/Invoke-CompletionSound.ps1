<#
.SYNOPSIS
    播放任务完成提示音
.DESCRIPTION
    在工作流成功结束时播放系统提示音，默认使用 Asterisk 声音（尊重系统静音与声音方案）。
    提示音属于装饰性副作用：播放失败只记录 Warning，不向上抛出，
    避免把已经完成的工作流变成失败。这一处理是「catch 记录后必须重抛」规则的定点例外。
    测试通过 -PlaySound 注入假实现，不产生真实声音。
.PARAMETER PlaySound
    实际执行发声的脚本块，默认（未注入或传入 $null）调用 [System.Media.SystemSounds]::Asterisk.Play()。
.EXAMPLE
    Invoke-CompletionSound
    播放默认完成提示音。
.EXAMPLE
    Invoke-CompletionSound -PlaySound { 'test' }
    注入假实现，用于单元测试。
.INPUTS
    无
.OUTPUTS
    [void]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Invoke-CompletionSound {
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [scriptblock]$PlaySound = $null
    )

    # 无条件构造默认实现（保证该行可被覆盖率统计）；未注入或显式传 $null 时回退到它
    [scriptblock]$DefaultPlaySound = { [System.Media.SystemSounds]::Asterisk.Play() }
    $PlaySound = $PlaySound ?? $DefaultPlaySound

    try {
        # 丢弃脚本块的返回值，保证函数本身符合 [OutputType([void])] 契约
        $null = & $PlaySound
    }
    catch {
        # 定点例外：提示音失败不影响已完成的工作流，记录后继续
        Write-LogEntry -Level Warning -Message "提示音播放失败: $($PSItem.Exception.Message)"
    }
}
