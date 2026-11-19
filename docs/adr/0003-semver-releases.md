# 版本号遵循 SemVer 2.0.0，由 `-Bump` 显式推进

**Status**: accepted（2026-11-19）

## 背景

`v1.0.0` 已发布（tag 指向 `0b4ac90`），之后 `main` 积累了 160 个提交，但
`source/IPAP.psd1` 的 `ModuleVersion` 一直停在 `1.0.0`。这带来两个问题：

- 直接发布必然撞 tag；
- 发布号是手工维护的，没有任何机制保证它「格式合法、单调递增、与 tag 一致」。

## 决策

1. **版本语义遵循 SemVer 2.0.0**：`MAJOR.MINOR.PATCH[-prerelease][+build]`。
   模块导出的函数视为对外契约——签名变更（增删参数、改语义）升 MAJOR，新增能力升 MINOR，
   纯修复升 PATCH。
2. **版本号只写在 `source/IPAP.psd1`**：`ModuleVersion` 存 `x.y.z`，预发布标签存
   `PrivateData.PSData.Prerelease`，两者组合成完整 SemVer 字符串。
3. **推进方式显式**：`.\build.ps1 -Task Release -Bump major|minor|patch`。
   以「最后一个版本 tag」为基准计算下一版，写回清单后再走打包/发布；
   不带 `-Bump` 时按清单现有版本执行。
4. **打包与发布前强制校验**（`Assert-VersionReady` / `Assert-RemoteTagFree`）：
   符合 SemVer 2.0.0、对应 tag 未被本地/远端占用、必须大于最后一个版本 tag。

## 考虑过的替代方案

- **只做手工维护 + 校验**：省掉写回逻辑，但「忘了改版本号」直接变成 tag 冲突或版本倒退，
  而这恰恰是能机械拦住的错误。
- **从 commit 前缀自动推断**（feat/fix/BREAKING CHANGE）：需要把提交改成英文前缀，
  与「Git commit message 必须使用简体中文」冲突；单人项目里自动推断的收益抵不上误判成本。

## 实测依据

- `[System.Management.Automation.SemanticVersion]::TryParse` **不能**当严格校验器：
  `01.2.3`、`1.2` 都能通过，`1.2.3+build.5` 会静默丢弃元数据。因此改用 semver.org 官方正则。
- 模块清单的 Loader 本身更严：`ModuleVersion = '2.0'`、`'01.2.3'`、`Prerelease = '01'`
  都会直接解析失败，但报错信息是通用的「无法将文件…分析为 PowerShell 数据文件」，
  所以在 `Get-ModuleVersion` 里补了一层可读的错误说明。
- `ModuleVersion` 是 `[version]` 类型，塞不进 `-beta.1`；预发布只能走 `PrivateData.PSData.Prerelease`。

## 影响

- 本次发布取 **2.0.0**：`New-ReadmeFile` 删除了 4 个参数并新增必填的 `-ProjectLevel`，
  属于破坏性变更；按「导出函数即契约」的判定升 MAJOR。
- 清单写回时保持 UTF-8 BOM 与 LF；写回前会剥掉残留的 BOM 字符，
  否则多次写回会叠加成多个 BOM 导致清单无法解析（已在实现中修复）。
- 预发布版本（如 `2.1.0-beta.1`）目前需手工写清单，`-Bump` 只推进正式版。
