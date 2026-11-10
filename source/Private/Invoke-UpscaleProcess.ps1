<#
.SYNOPSIS
    执行单张图片的高清化处理
.DESCRIPTION
    调用指定引擎处理一张图片，并返回统一结果对象。
    成功判定：
    - RealCugan：只看输出文件是否存在（实测退出码不可靠，解码/编码失败仍可能返回 0）；
    - FFmpeg：退出码为 0 且输出文件存在。
    外部进程调用通过 InvokeProcess 注入，默认直接执行真实可执行文件。
    两个引擎都会重定向并丢弃 stderr：Real-CUGAN 会把 GPU 进度写到 stderr，
    $ErrorActionPreference = 'Stop' 时若直接透传会被误判为终止错误。
.PARAMETER Image
    图片文件对象，需包含 Name 属性。
.PARAMETER OutputPath
    输出图片完整路径。
.PARAMETER Arguments
    已构造好的命令行参数数组。
.PARAMETER Engine
    处理引擎（RealCugan / FFmpeg）。
.PARAMETER ExePath
    引擎可执行文件路径。
.PARAMETER InvokeProcess
    进程调用适配器，返回退出码；默认直接调用可执行文件。
.EXAMPLE
    Invoke-UpscaleProcess -Image $image -OutputPath 'b.webp' -Arguments $args -Engine 'RealCugan' -ExePath $exe
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
        [ValidateSet('RealCugan', 'FFmpeg')]
        [string]$Engine,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ExePath,

        # 默认适配器：两个引擎都捕获并丢弃输出（含 stderr），只返回退出码。
        # Real-CUGAN 会把 GPU 进度写到 stderr；在 $ErrorActionPreference = 'Stop' 下
        # 直接透传会被当作终止错误，导致整个并行批次失败。
        [scriptblock]$InvokeProcess = {
            param([string]$Path, [string[]]$Arguments)
            $null = & $Path @Arguments 2>&1
            return $LASTEXITCODE
        }
    )

    try {
        [int]$exitCode = & $InvokeProcess $ExePath $Arguments

        [bool]$success = if ($Engine -eq 'RealCugan') {
            # RealCugan 退出码不可靠：只以输出文件是否存在判定成功
            Test-Path -LiteralPath $OutputPath
        }
        else {
            $exitCode -eq 0 -and (Test-Path -LiteralPath $OutputPath)
        }

        return [PSCustomObject]@{
            Success = $success
            Image   = $Image.Name
            Error   = ''
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Image   = $Image.Name
            Error   = $PSItem.Exception.Message
        }
    }
}
