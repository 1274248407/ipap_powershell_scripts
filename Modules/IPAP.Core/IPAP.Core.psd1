@{
    RootModule        = 'IPAP.Core.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
    Author            = 'IPAP Team'
    CompanyName       = 'IPAP'
    Copyright         = '(c) 2026 IPAP Team. All rights reserved.'
    Description       = '提供日志系统和通用工具函数。配置管理已迁移至 IPAP.Configuration 模块。'
    PowerShellVersion = '7.0'
    RequiredModules   = @('IPAP.Configuration')
    FunctionsToExport = @(
        'Get-NaturalSortKey',
        'Get-FfmpegPath',
        'Get-FfprobePath',
        'Get-RealCuganExePath',
        'Get-SupportedImageFormat',
        'Get-AppConfiguration',
        'Get-PathConfiguration'
    )
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('IPAP', 'Core', 'Workflow')
            ProjectUri = 'https://github.com/ipap-team/ipap-workflow'
        }
    }
}
