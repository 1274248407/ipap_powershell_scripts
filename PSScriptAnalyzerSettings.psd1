@{
    # 启用所有内置严重级别的规则（含 Error, Warning, Information 和 TBD）
    Severity     = @('Error', 'Warning', 'Information', 'TBD')
    # 排除 BOM 规则：pwsh7 默认 UTF8-noBOM，项目规则禁止依赖 BOM 行为
    # 排除别名规则：项目允许使用 PowerShell 别名（如 Copy, Remove, Move 等）
    ExcludeRules = @('PSUseBOMForUnicodeEncodedFile', 'PSAvoidUsingCmdletAliases')
}
