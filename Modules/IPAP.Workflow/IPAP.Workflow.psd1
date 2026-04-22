@{
    RootModule = 'IPAP.Workflow.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'd4e5f6a7-b8c9-4d5e-1f2a-3b4c5d6e7f8a'
    Author = 'IPAP Team'
    CompanyName = 'IPAP'
    Copyright = '(c) 2026 IPAP Team. All rights reserved.'
    Description = '提供完整的 IPAP 工作流执行逻辑，包括环境初始化、项目创建、图片分析和处理。'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Start-IPAPWorkflow'
    )
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('IPAP', 'Workflow', 'Main')
            ProjectUri = 'https://github.com/ipap-team/ipap-workflow'
        }
    }
}
