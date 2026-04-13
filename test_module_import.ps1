# 测试模块导入和函数调用
Import-Module -Name '.\ipap_workflow.psm1' -Force

# 测试 Get-IpapConfig 函数
try {
    Write-Host '测试 Get-IpapConfig 函数...'
    $config = Get-IpapConfig -ConfigPath '.\config.toml.example'
    Write-Host '✅ Get-IpapConfig 函数调用成功'
    Write-Host "配置类型： $($config.GetType())"
} catch {
    Write-Host "❌ Get-IpapConfig 函数调用失败: $($PSItem.Exception.Message)"
}

# 测试 Initialize-IpapModule 函数
try {
    Write-Host '\n测试 Initialize-IpapModule 函数...'
    $result = Initialize-IpapModule
    Write-Host "✅ Initialize-IpapModule 函数调用成功，返回值: $result"
} catch {
    Write-Host "❌ Initialize-IpapModule 函数调用失败: $($PSItem.Exception.Message)"
}

Write-Host '\n测试完成！'