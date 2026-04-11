# 测试 IPAP Workflow PowerShell 模块的基本功能

# 导入模块
Import-Module -Name '.\ipap_workflow.psm1' -Force

Write-Host "=== 测试 IPAP Workflow 模块基本功能 ===" -ForegroundColor Cyan

# 测试模块是否成功加载
if (Get-Module -Name 'ipap_workflow') {
    Write-Host "✅ 模块加载成功" -ForegroundColor Green
} else {
    Write-Host "❌ 模块加载失败" -ForegroundColor Red
    exit 1
}

# 测试函数是否存在
$functions = @(
    'Initialize-IpapModule',
    'Get-IpapConfig',
    'Test-IpapConfig',
    'New-ExampleConfig',
    'Get-IpapImageFiles',
    'Get-IpapImageInfo',
    'New-IpapProjectStructure',
    'Copy-IpapImagesAndAnalyze',
    'Invoke-IpapUpscaling',
    'Move-IpapOriginalSource',
    'Invoke-IpapParallelProcessing',
    'Process-IpapImages',
    'New-IpapProjectFiles',
    'Set-IpapProject',
    'Invoke-IpapWorkflow',
    'Invoke-IpapCompleteWorkflow'
)

$allFunctionsExist = $true
foreach ($function in $functions) {
    if (Get-Command -Name $function -ErrorAction SilentlyContinue) {
        Write-Host "  ✅ 函数 $function 存在" -ForegroundColor Green
    } else {
        Write-Host "  ❌ 函数 $function 不存在" -ForegroundColor Red
        $allFunctionsExist = $false
    }
}

# 测试帮助文档
Write-Host "\n=== 测试帮助文档 ===" -ForegroundColor Cyan
foreach ($function in $functions) {
    try {
        $help = Get-Help -Name $function -ErrorAction Stop
        if ($help.Synopsis) {
            Write-Host "  ✅ 函数 $function 有帮助文档" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  函数 $function 帮助文档不完整" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ❌ 函数 $function 获取帮助文档失败: $($PSItem.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "\n=== 测试完成 ===" -ForegroundColor Cyan
if ($allFunctionsExist) {
    Write-Host "✅ 所有测试通过！PowerShell 模块功能正常。" -ForegroundColor Green
} else {
    Write-Host "❌ 部分测试失败，需要检查。" -ForegroundColor Red
}

Write-Host "\n测试完成！" -ForegroundColor Cyan