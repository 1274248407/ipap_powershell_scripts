$testDir = 'tests'
$fixed = 0
Get-ChildItem -Path $testDir -Filter '*.ps1' -Recurse | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    # 检测双重 BOM（EF BB BF EF BB BF）
    if ($bytes.Length -ge 6 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF -and $bytes[3] -eq 0xEF -and $bytes[4] -eq 0xBB -and $bytes[5] -eq 0xBF)
    {
        $newBytes = $bytes[3..($bytes.Length - 1)]
        [System.IO.File]::WriteAllBytes($_.FullName, $newBytes)
        Write-Output "Fixed: $($_.Name)"
        $fixed++
    }
}
Write-Output "Fixed $fixed files"
