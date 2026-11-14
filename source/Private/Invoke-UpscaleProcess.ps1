<#
.SYNOPSIS
    执行单张图片的高清化处理
.DESCRIPTION
    调用指定引擎处理一张图片，并返回统一结果对象。
    成功判定：
    - RealCugan：只看输出文件是否存在（实测退出码不可靠，解码/编码失败仍可能返回 0）；
    - FFmpeg / Webp：退出码为 0 且输出文件存在。
    外部进程调用通过 InvokeProcess 注入，默认直接执行真实可执行文件。
    各引擎都会重定向并丢弃 stderr：Real-CUGAN 会把 GPU 进度写到 stderr，
    $ErrorActionPreference = 'Stop' 时若直接透传会被误判为终止错误。

    指定 -CopyOriginalOnFailure 时，失败会把原图复制到输出目录并保留原扩展名。
    这是转码路径的兜底：宁可留下一个格式不对的页面，也不能整页丢失；
    是否算通过由 Test-UpscaleResult 的格式校验判定，不会被静默当成成功。
.PARAMETER Image
    图片文件对象，需包含 Name 属性；-CopyOriginalOnFailure 时还需 FullName。
.PARAMETER OutputPath
    输出图片完整路径。
.PARAMETER Arguments
    已构造好的命令行参数数组。
.PARAMETER Engine
    处理引擎（RealCugan / FFmpeg / Webp）。
.PARAMETER ExePath
    引擎可执行文件路径。
.PARAMETER CopyOriginalOnFailure
    失败时把原图复制到输出目录（保留原扩展名），用于避免转码失败导致整页丢失。
.PARAMETER InvokeProcess
    进程调用适配器，返回退出码；默认直接调用可执行文件。
.EXAMPLE
    Invoke-UpscaleProcess -Image $image -OutputPath 'b.webp' -Arguments $args -Engine 'RealCugan' -ExePath $exe
.EXAMPLE
    Invoke-UpscaleProcess -Image $image -OutputPath 'b.webp' -Arguments $args -Engine 'Webp' -ExePath $ffmpeg -CopyOriginalOnFailure
.INPUTS
    无
.OUTPUTS
    PSCustomObject（Success / Image / Error）
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Invoke-UpscaleProcess {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Image,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [ValidateSet('RealCugan', 'FFmpeg', 'Webp')]
        [string]$Engine,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ExePath,

        [switch]$CopyOriginalOnFailure,

        # 默认适配器：所有引擎都捕获并丢弃输出（含 stderr），只返回退出码。
        # Real-CUGAN 会把 GPU 进度写到 stderr；在 $ErrorActionPreference = 'Stop' 下
        # 直接透传会被当作终止错误，导致整个并行批次失败。
        [scriptblock]$InvokeProcess = {
            param([string]$Path, [string[]]$Arguments)
            $null = & $Path @Arguments 2>&1
            return $LASTEXITCODE
        }
    )

    [bool]$success = $false
    [string]$errorMessage = ''

    try {
        [int]$exitCode = & $InvokeProcess $ExePath $Arguments

        $success = if ($Engine -eq 'RealCugan') {
            # RealCugan 退出码不可靠：只以输出文件是否存在判定成功
            Test-Path -LiteralPath $OutputPath
        }
        else {
            $exitCode -eq 0 -and (Test-Path -LiteralPath $OutputPath)
        }
    }
    catch {
        $errorMessage = $PSItem.Exception.Message
    }

    # 转码兜底：失败时保留原图（原扩展名），由上层格式校验判为失败而不是悄悄放过
    if (-not $success -and $CopyOriginalOnFailure) {
        try {
            [string]$fallbackPath = Join-Path ([System.IO.Path]::GetDirectoryName($OutputPath)) ([System.IO.Path]::GetFileName($Image.FullName))
            Copy-Item -LiteralPath $Image.FullName -Destination $fallbackPath -Force -ErrorAction Stop
        }
        catch {
            [string]$fallbackError = "回退复制原图失败: $($PSItem.Exception.Message)"
            $errorMessage = $errorMessage ? "$errorMessage; $fallbackError" : $fallbackError
        }
    }

    return [PSCustomObject]@{
        Success = $success
        Image   = $Image.Name
        Error   = $errorMessage
    }
}
