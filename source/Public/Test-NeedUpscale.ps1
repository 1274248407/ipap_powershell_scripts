<#
.SYNOPSIS
    判断是否需要高清化处理
.DESCRIPTION
    根据平均文件大小判断是否需要进行图片高清化处理，阈值为 1000KB。
.PARAMETER AverageSize
    (double, Mandatory) 平均文件大小（KB）。
    （适用于所有参数集）
.EXAMPLE
    Test-NeedUpscale -AverageSize 500
    平均文件大小小于 1000KB，返回 $true。
.EXAMPLE
    Test-NeedUpscale -AverageSize 1500
    平均文件大小大于等于 1000KB，返回 $false。
.INPUTS
    double
.OUTPUTS
    bool
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>

function Test-NeedUpscale
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [Nullable[double]]$AverageSize
    )

    if ($null -eq $AverageSize)
    {
        throw [System.ArgumentNullException]::new('AverageSize', '平均文件大小不能为 null')
    }

    $threshold = 1000

    if ($AverageSize -lt $threshold)
    {
        Write-LogEntry -Level Info -Message "平均文件大小 $([math]::Round($AverageSize, 2)) KB < $threshold KB，需要高清化"
        return $true
    }
    else
    {
        Write-LogEntry -Level Info -Message "平均文件大小 $([math]::Round($AverageSize, 2)) KB >= $threshold KB，跳过高清化"
        return $false
    }
}

