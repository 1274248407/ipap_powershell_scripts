@{
    RootModule = 'IPAP.Configuration.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5f'
    Author = 'lucas_gold'
    Description = 'IPAP 配置管理模块'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-Configuration', 'Reset-Configuration', 'Test-ConfigurationInitialized', 'Confirm-ProjectConfiguration')
}
