# 统一使用 K&R（One True Brace Style）花括号风格

**Status**: accepted（2026-10-17）

## 背景

启用 PSScriptAnalyzer 的 6 条格式化规则时，必须先选定花括号风格。仓库历史代码以 Allman 为主
（`{` 独占一行），但测试文件已是 K&R；生态口径也明确偏向 K&R：Microsoft Learn 的
`PSPlaceOpenBrace.OnSameLine` 默认值是 `$true`，PoshCode《PowerShell Practice and Style》
推荐 One True Brace Style。

## 决策

采用 K&R（`OnSameLine = $true`），并用 `Invoke-Formatter` 一次性重排源码。

## 考虑过的替代方案

- **保持 Allman**：只需改 23 处、diff 最小；但任何生成器、代码片段或外部代码默认都是 K&R，
  每次都要手工改回，且会与测试文件的既有风格长期并存。
- **不启用花括号规则**：等于放弃「用规则守住格式」这个初衷，只保留空白类检查。

## 影响

- 一次性重排 26 个文件、251 处花括号、681 行 diff，单独一个纯格式化提交（`24684dd`）；
  其中 8 个文件因混合行尾被 `Invoke-Formatter` 拒绝，花括号为手工合并（详见
  `docs/将来要改的地方.md` 的「8 个源文件为混合行尾」条目）。
- 编辑器侧同步配置 `powershell.codeFormatting.*`（`preset = Custom` 加逐项对齐），
  让「Format Document」与分析器规则保持一致。
- 测试文件无需改动即天然合规（它们本来就是 K&R）。
