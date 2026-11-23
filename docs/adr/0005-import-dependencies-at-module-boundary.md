# PSToml 在模块加载时导入，函数内只做可用性检查

**Status**: accepted（2026-11-23）

## 背景

v3.0.0 把项目记录改成 `README.toml`，读它依赖 PSToml 的 `ConvertFrom-Toml`。
发布后实测发布包（`<pkg>/IPAP/` + `<pkg>/RequiredModules/`）在干净机器上**读不回**这份文件：
`README.toml` 照常写出，但读回来永远是 `$null`，于是自动续跑永不触发、
`[progress]` / `[notes]` / `[todo]` 每次运行被重置成默认值，日志里只有一行 Warning。

排查后是三个事实叠在一起：

1. **`-Scope Local` 的导入活不过所属作用域。** `IPAPConfiguration.LoadSettings` 里
   `Import-Module ... -Scope Local` 只落在类方法自己的作用域，方法返回后
   `ConvertFrom-Toml` 就从模块中消失（实测：模块内 `Get-Command` 为 `False`）。
   配置读取之所以正常，是因为它与导入发生在同一个方法里。
2. **`-Force` 会拆除模块作用域那一份。** 先 `Remove-Module` 再导入，
   于是即使在 `IPAP.psm1` 里导入成功，配置加载后也会再次消失（实测：
   加载后 `True` → `Get-Configuration` 之后 `False`）。
3. **按需导入的候选路径按开发仓库布局写。** `<repo>/source/Private` 往上两级是仓库根，
   `<repo>/output/RequiredModules/PSToml` 存在；打包后 `<pkg>/IPAP/Private` 往上两级是 `<pkg>`，
   找的是 `<pkg>/output/RequiredModules/PSToml`，不存在。

开发仓库复现不了（`output/RequiredModules/PSToml` 恰好存在），测试也没抓到——
所有测试文件的 `BeforeAll` 都 `Import-Module PSToml -Global`，等于替被测代码把依赖装好了。

## 决策

**外部依赖在模块边界装好，函数不自己找依赖。**

1. `IPAP.psm1` 在 dot-source 完成后导入 PSToml 一次，且不带 `-Scope`——
   在模块脚本里导入即落在模块作用域，调用方会话不受污染（实测：模块内 `True`、调用方 `False`）。
2. 候选路径必须同时覆盖两种布局：
   - 发布包：`<pkg>/IPAP/RequiredModules`、`<pkg>/RequiredModules`
   - 开发仓库：`<repo>/output/RequiredModules`
3. 函数内只做可用性检查（`Get-Command 'ConvertFrom-Toml'`），不做导入；
   不可用时按「无记录」处理并记 Warning，**不把一份读不出来的好文件改名成 `.bad`**。
4. 类内导入保留作为兜底，但去掉 `-Force`，避免把模块作用域那份拆掉。

## 考虑过的替代方案

- **保持每个函数自己摸候选路径**（v3.0.0 的做法）：等于让每个用依赖的函数各维护一份
  「依赖在哪」的知识，且每份都要覆盖两种布局；漏一份就是这次的现象。
- **用 `-Scope Global` 导入**：能跨作用域，但污染调用方会话（变量、命令都暴露给用户脚本），
  而且 `-Force` 依然会把它拆掉，治标不治本。
- **只改候选路径、不移动导入点**：能修好发布包，但保留「函数运行时才发现依赖缺失」的失败模式，
  且失败表现为静默降级（Warning + 返回 `$null`），下一次还会以别的方式复发。

## 依据

| 实验（发布包布局 + 清空 `PSModulePath`） | 结果 |
|---|---|
| 仅 `IPAP.psm1` 导入，类内仍用 `-Force` | 加载后 `True` → `Get-Configuration` 之后 `False` |
| 类内去掉 `-Force` | 加载后 `True` → `Get-Configuration` 之后 `True` |
| 此状态下调用 `Get-ReadmeToml` | 读到 `status=running / level=0` |
| 调用方作用域是否出现 `ConvertFrom-Toml` | `False`（未污染） |

补充：`Get-Command` 会按 `PSModulePath` 自动加载模块，本机已装 PSToml 时会掩盖这个问题。
因此验证必须同时断开「已加载的模块」与 `PSModulePath`，否则测不出干净机器的行为。
测试里对应一条用例：清空 `PSModulePath` + `Remove-Module PSToml` + 重新导入 IPAP，
再断言模块内能看见 `ConvertFrom-Toml`。

## 影响

- `Get-ReadmeToml` 从 60 行降到 40 行左右，删掉了整个候选路径循环。
- 新增外部依赖时照此办理：**导入只写在 `IPAP.psm1`，函数内只判断可用性**。
- 打包验证不能只看「开发仓库能跑」；发布包布局（`IPAP/` 与 `RequiredModules/` 同级）
  必须在干净 `PSModulePath` 下实跑过一次。
