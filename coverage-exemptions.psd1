@{
    # 覆盖率结构豁免清单（唯一事实源）
    # 规则：只登记测试无法触达的行（子 runspace 注入、默认 IO 适配器）；
    # build.ps1 -Task Test 会双向校验：未登记的缺失行失败，已不再缺失的条目也失败。
    Exemptions = @(
        @{
            File   = 'Invoke-MultiLineReader.ps1'
            Lines  = @(31)
            Reason = '默认 [Console]::ReadKey 适配器；非交互环境无法调用，循环逻辑由注入的假 ReadKey 覆盖'
            Since  = '2026-11-05'
        }
        @{
            File   = 'Get-ImageLevel.ps1'
            Lines  = @(54, 55)
            Reason = 'ForEach-Object -Parallel 子 runspace 注入；Pester 覆盖率插桩不跨 runspace'
            Since  = '2026-11-05'
        }
        @{
            File   = 'Invoke-ParallelUpscale.ps1'
            Lines  = @(112, 113, 114)
            Reason = 'ForEach-Object -Parallel 子 runspace 注入；Pester 覆盖率插桩不跨 runspace'
            Since  = '2026-11-05'
        }
    )
}
