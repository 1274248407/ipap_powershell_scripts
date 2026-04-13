# IPAP Workflow PowerShell 模块清单文件

@{    
    ModuleVersion     = '0.1.0'
    GUID              = 'A1B2C3D4-E5F6-4567-89AB-CDEF01234567'
    Author            = 'IPAP Workflow Team'
    CompanyName       = 'IPAP Workflow'
    Copyright         = '© 2026 IPAP Workflow. All rights reserved.'
    Description       = 'IPAP Workflow PowerShell 模块，用于漫画翻译前的图像预处理'
    PowerShellVersion = '7.0'
    RootModule        = 'ipap_workflow.psm1'
    RequiredModules   = @()
    FunctionsToExport = @(
        'Invoke-IpapWorkflow',
        'Move-IpapOriginalSource',
        'Get-IpapImageInfo'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
