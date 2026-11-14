# IPAP PowerShell 项目指令

PowerShell 7 图像处理自动化项目（ipap_workflow）。修改任何 `.ps1` / `.psm1` / `.Tests.ps1` 文件前，先阅读本文件；细节规范按需参考 `docs/project-rules/powershell-7-standard-project-rules.md`。

## 构建与测试命令

- **构建**：`.\build.ps1 -Task Build`（打包模块到 `output/IPAP/`）
- **静态分析**：`.\build.ps1 -Task Analyze`（PSScriptAnalyzer + AST 契约检查 `Invoke-OutputTypeAudit`）
- **测试**：`.\build.ps1 -Task Test`（自动先执行 Build + Analyze；Pester v5 单元 + 集成）
- **打包**：`.\build.ps1 -Task Pack`（依赖链：Build → Analyze → Test）
- **发布**：`.\build.ps1 -Task Release`（依赖链：Pack，含 git commit/tag/push + gh release）
- 直接跑测试：`Invoke-Pester .\tests` 或按文件 `.\tests\Unit\Public\IPAP_*.Unit.Tests.ps1`

## 编码规范（权威）

- **强类型契约**：所有变量、param 参数、返回值显式标注类型；函数必须含 `[CmdletBinding()]` 与 `[OutputType()]`（无输出用 `[OutputType([void])]`）。
  - 自定义类返回值用字符串形式：`[OutputType('ClassName')]`；内置类型用类型字面量。`.OUTPUTS` 与实际 return 必须一致。
  - `[OutputType()]` 声明的是单个元素类型，不是集合类型。
- **PS7 新语法强制**：三元 `条件 ? 真 : 假`、Null 合并 `??` / `??=`、管道链 `&&` / `||`；禁止用旧语法替代。
- **命名**：自定义变量/函数/参数一律 PascalCase；禁止 `$_`，一律使用 `$PSItem`。
  - 重构旧代码时主动修复不符合 PascalCase 或缺失类型声明的代码块。
- **防御性编程**：IO 与网络操作必须包裹 try-catch；`Write-LogEntry` 四个级别均为**纯日志输出**（只写终端，不抛异常、不中断执行）；需要"记录并中断"时，先调用 `Write-LogEntry -Level Error` 记录现场，再在同一代码块内显式 `throw` 带类型异常（如 `[System.ArgumentException]`、`[System.IO.IOException]`），日志与控制流分离；catch 记录后必须重抛，禁止吞异常。
- **帮助文档**：每个函数/类/类方法上方必须有完整 Help-Based Help 注释块，作者固定为 `lucas_gold`，使用简体中文。
- **注释语言**：所有注释（单行 `#` 与块注释 `<#...#>`）必须使用简体中文；变量、函数名等标识符保持英文。
- **测试（Pester v5，v5.3.0+）**：
  - 文件命名 `*.Tests.ps1`：单元 `tests/Unit/Public/IPAP_*.Unit.Tests.ps1`，集成 `tests/Integration/*.Integration.Tests.ps1`，命名模式 `{ModuleName}_{FunctionName}.{Scope}.Tests.ps1`。
  - 单元测试完全隔离外部依赖用 Mock；集成测试用 `TestDrive` 真实文件操作、Mock 屏蔽日志输出、只覆盖核心正向路径与关键失败路径。
  - 只 Mock 模块外部依赖；Mock 定义在 `BeforeEach` 中；Mock 模块内命令必须用 `-ModuleName`。
  - 断言精确，避免模糊字符串匹配；测试之间不共享状态，`AfterEach/AfterAll` 清理。
  - 编写测试时参考 `docs/单元测试方法论.md` 的5级分级与纯函数/副作用函数原则。

## Git 提交

- Git commit message 必须使用**简体中文**。

## 参考

- 完整规则细节（类 Help 模板示例、断言/Mock 细则、build.ps1 自动检查机制等）见 `docs/project-rules/powershell-7-standard-project-rules.md`。
- 文档根目录固定为 `docs/`：流程/方法论文档放 `docs/`，架构决策记录放 `docs/adr/`，术语表留在仓库根 `GLOSSARY.md`；不要再新建 `doc/`。