@{
    RootModule = 'IPAP.ProjectManager.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'c3d4e5f6-a7b8-4c5d-0e1f-2a3b4c5d6e7f'
    Author = 'IPAP Team'
    CompanyName = 'IPAP'
    Copyright = '(c) 2026 IPAP Team. All rights reserved.'
    Description = '提供项目目录结构创建、README 文件生成和翻译文件管理功能。'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'New-ProjectStructure',
        'New-ReadmeFile',
        'New-TranslationFiles',
        'Get-ProjectBriefInfo'
    )
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('IPAP', 'Project', 'Manager', 'Workflow')
            ProjectUri = 'https://github.com/ipap-team/ipap-workflow'
        }
    }
}
