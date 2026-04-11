# Get-IpapConfig 函数的测试脚本

# 导入模块
Import-Module -Name '.\ipap workflow.psm1' -Force -ErrorAction Stop

# 测试 Get-IpapConfig 函数
try
{
    Write-Host '正在测试 Get-IpapConfig...'
    $config = Get-IpapConfig
    Write-Host '配置加载成功！'
    Write-Host "配置类型： $($config.GetType())"
    Write-Host "配置内容： $config"
    
    # 测试访问特定的配置值
    Write-Host "基础项目目录： $($config.paths.base_project_dir)"
    Write-Host "最大工人数： $($config.app_settings.max_workers)"
    Write-Host "放大比例： $($config.upscale.upscale_ratio)"
    Write-Host "已启用 WebP： $($config.webp.enabled)"
}
catch
{
    Write-Host "错误： $($PSItem.Exception.Message)"
}
