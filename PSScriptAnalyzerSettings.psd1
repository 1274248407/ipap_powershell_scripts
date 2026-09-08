@{
    # 启用所有内置严重级别的规则（含 Error, Warning, Information 和 TBD）
    Severity     = @('Error', 'Warning', 'Information', 'TBD')
    # 排除 BOM 规则：pwsh7 默认 UTF8-noBOM，项目规则禁止依赖 BOM 行为
    # 排除别名规则：项目允许使用 PowerShell 别名（如 Copy, Remove, Move 等）
    # 排除 Write-Host 规则：仅入口脚本 Main.ps1 使用（交互式 UI 输出，模块源码禁止使用）
    # 排除全局变量规则：仅用于模块级配置实例 Global:IPAPConfigInstance（跨函数共享的设计约定）
    ExcludeRules = @('PSUseBOMForUnicodeEncodedFile', 'PSAvoidUsingCmdletAliases', 'PSAvoidUsingWriteHost', 'PSAvoidGlobalVars')
}
