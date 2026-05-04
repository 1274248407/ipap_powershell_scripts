@{
    RootModule        = 'IPAP.Core.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
    Author            = 'IPAP Team'
    CompanyName       = 'IPAP'
    Copyright         = '(c) 2026 IPAP Team. All rights reserved.'
    Description       = '提供日志系统、配置解析和通用工具函数。'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-Config',
        'Get-NaturalSortKey',
        'Get-RealCuganExePath',
        'Initialize-Environment'
    )
    VariablesToExport = @(
        'BinPath',
        'ConfigPath',
        'TomlJsonExePath',
        'Settings',
        'SupportedImageFormats',
        'DefaultSettings',
        'RealCuganExePath'
    )
    PrivateData       = @{
        PSData = @{
            Tags       = @('IPAP', 'Core', 'Workflow')
            ProjectUri = 'https://github.com/ipap-team/ipap-workflow'
        }
    }
}
