@{
    RootModule = 'IPAP.ImageProcessor.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'b2c3d4e5-f6a7-4b5c-9d0e-1f2a3b4c5d6e'
    Author = 'IPAP Team'
    CompanyName = 'IPAP'
    Copyright = '(c) 2026 IPAP Team. All rights reserved.'
    Description = '提供图片分析、高清化处理和并行处理功能。'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-ImageInfo',
        'Test-NeedUpscale',
        'Invoke-ImageUpscale',
        'Invoke-ParallelUpscale',
        'Initialize-ImageProcessor'
    )
    VariablesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('IPAP', 'Image', 'Processor', 'Workflow')
            ProjectUri = 'https://github.com/ipap-team/ipap-workflow'
        }
    }
}
