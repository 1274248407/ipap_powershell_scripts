@{
    RootModule        = 'IPAP.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f3a9d2c1-7b4e-4c8a-9d6f-1e2a3b4c5d6e'
    Author            = 'IPAP Team'
    CompanyName       = 'IPAP'
    Copyright         = '(c) 2026 IPAP Team. All rights reserved.'
    Description       = 'IPAP 漫画翻译工作流自动化工具：项目管理、图片高清化、配置管理与端到端工作流编排。'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-Configuration',
        'Reset-Configuration',
        'Test-ConfigurationInitialized',
        'Confirm-ProjectConfiguration',
        'Get-NaturalSortKey',
        'Get-FfmpegPath',
        'Get-FfprobePath',
        'Get-RealCuganExePath',
        'Get-SupportedImageFormat',
        'Test-SupportedImageFormat',
        'Get-AppConfiguration',
        'Get-PathConfiguration',
        'Get-ImageInfo',
        'Test-NeedUpscale',
        'Get-ImageLevel',
        'Invoke-ParallelUpscale',
        'Rename-FilesBySize',
        'New-ProjectStructure',
        'New-ReadmeFile',
        'Read-MultiLineInput',
        'Get-ProjectBriefInfo',
        'Start-IPAPWorkflow',
        'Select-NonTextImage',
        'Test-UpscaleResult',
        'Write-LogEntry'
    )
    VariablesToExport = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('IPAP', 'Workflow', 'ImageProcessing', 'Upscale')
            ProjectUri = 'https://github.com/1274248407'
        }
    }
}
