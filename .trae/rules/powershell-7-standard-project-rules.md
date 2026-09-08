﻿﻿﻿---
description: "PowerShell 7 专项开发规则 - 适用于项目中的所有 .ps1/.psm1 文件"
---

# PowerShell 7 专项开发规则

## 1. 语法与架构硬性约束

- **强类型契约**：禁止使用弱类型定义。必须为所有变量、函数参数（param 块）及返回值显式标注类型。
  - 示例：`[string]$UserName = "Lucas"`, `[int]$RetryCount = 3`
- **标准架构**：所有函数必须包含 `[CmdletBinding()]` 和 `[OutputType()]` 属性，并统一使用 `param()` 块定义参数。
  - **元素类型语义**：`[OutputType()]` 声明单个输出对象的类型，不声明集合类型。示例：输出多个文件的函数声明 `[OutputType([System.IO.FileInfo])]` 而非 `[OutputType([System.IO.FileInfo[]])]`（与 PowerShell 官方惯例及 `PSUseOutputTypeCorrectly` 检查逻辑一致）。
  - **无输出函数**：显式声明 `[OutputType([void])]`。
  - **类方法豁免**：PowerShell 类方法不支持 `[OutputType()]` 属性，返回契约由方法签名的静态返回类型承担（如 `[string] GetProjectName()`）。
  - **自定义类返回值**：函数返回模块内自定义类的实例时，必须使用**字符串形式**声明 `[OutputType('ClassName')]`。类型字面量形式（`[OutputType([ClassName])]`）的实参在调用者上下文解析，模块类在全局会话状态不可见，将导致运行时 `Unable to find type` 终止错误。内置类型（string、hashtable、bool 等）仍使用类型字面量形式。
  - **一致性要求**：`[OutputType()]` 声明、Help 块 `.OUTPUTS` 与函数实际 return 行为三者必须一致。
  - **自动检查**：`build.ps1` 的 Analyze task 含 AST 契约检查（`Invoke-OutputTypeAudit`），缺失声明将阻断构建。

## 2. PowerShell 7 新语法强制

- **必须使用 PS7 新语法**：在编写代码时，必须优先使用 PowerShell 7 引入的新语法特性，禁止使用旧语法替代方案。
- **Ternary 操作符（三元表达式）**：
  - 必须使用 `条件 ? 真值 : 假值` 替代 `if/else` 赋值语句。
  - 示例：`[string]$Status = $IsValid ? "有效" : "无效"`
- **Null 合并操作符**：
  - 必须使用 `??` 和 `??=` 替代空值检查逻辑。
  - 示例：`[string]$Name = $User.Name ?? "匿名用户"`
  - 示例：`$Config ??= Get-DefaultConfig`
- **Pipeline 链操作符**：
  - 必须使用 `&&`（成功时继续）和 `||`（失败时继续）替代顺序执行的命令。
  - 示例：`Test-Path $Path && Get-Content $Path`
  - 示例：`Invoke-RestMethod $Url || throw "请求失败"`

## 3. 命名与风格规范

- **PascalCase 强制化**：所有自定义变量名、函数名、参数名必须使用 PascalCase（大驼峰命名法）。
  - *例外情况*：系统内置自动变量（如 `$PSBoundParameters`, `$PSItem`, `$args`, `$foreach`, `$HOME` 等）保持原样，不强制执行。
- **$PSItem 强制化**：禁止使用 `$_`，必须使用`$PSItem` 以提高可读性。
  - 适用于所有场景：`ForEach-Object`、`Where-Object`、`switch` 语句、管道脚本块等。
- **重构指令**：在修改或重构现有代码时，AI 必须主动修复不符合 PascalCase 规范或缺失类型声明的旧代码块。

## 4. 防御性编程 (Error Handling)

- **风险驱动的 Try-Catch**：
  - 凡涉及 **IO 操作**（文件读取、写入、移动等）的逻辑，必须包裹在 `try-catch` 结构中。
  - 凡涉及 **网络请求**（如 `Invoke-RestMethod`, `Invoke-WebRequest`）的逻辑，必须包裹在 `try-catch` 结构中。
  - `catch` 块应包含明确的异常处理逻辑（如 `throw $PSItem`）。
- **日志与控制流分离（Write-LogEntry 契约）**：
  - `Write-LogEntry` 是**纯日志函数**：任何级别（含 Error）都只记录，**不抛出异常、不中断执行**。
  - 需要"记录并中断"时：先 `Write-LogEntry -Level Error` 记录现场，随后**显式 throw 带明确类型的异常**（如 `[System.ArgumentException]`、`[System.IO.DirectoryNotFoundException]`、`[System.InvalidOperationException]`）。
  - `catch` 块记录上下文后必须重抛（`throw $PSItem` 或包装异常 `throw [System.IO.IOException]::new($消息, $PSItem.Exception)`），**禁止吞异常**；顶层保证进程退出码非零。

## 5. 强制 Help-Based Help 模板

每个定义的函数上方必须包含以下格式的注释块，作者信息固定如下：

```powershell
<#
.SYNOPSIS
    [简要描述函数功能]
.DESCRIPTION
    [详细解释函数的工作原理、逻辑及适用场景]
.PARAMETER [参数名]
    (类型) [该参数的作用及说明]
.EXAMPLE
    [具体的用法示例]
.INPUTS
    [输入对象类型]
.OUTPUTS
    [输出对象类型]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
```

### 5.1 PowerShell 类 Help-Based Help 规范

PowerShell 类及其成员也需要完整的 Help-Based Help 文档。

#### 5.1.1 类定义 Help

每个类定义上方必须包含以下格式的注释块：

```powershell
<#
.SYNOPSIS
    [简要描述类的功能]
.DESCRIPTION
    [详细解释类的作用、职责及设计意图]
.EXAMPLE
    [类的使用示例]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
class ClassName
{
    # 属性定义...
}
```

#### 5.1.2 类属性 Help

每个类属性上方必须添加单行注释说明其用途：

```powershell
<#
.SYNOPSIS
    [简要描述类的功能]
.DESCRIPTION
    [详细解释类的作用]
.NOTES
    Author:  lucas_gold
    Website: https://github.com/1274248407
#>
class ClassName
{
    # 属性的简要说明
    [string]$PropertyName

    # 另一个属性的简要说明
    [int]$AnotherProperty
}
```

#### 5.1.3 类方法 Help

每个类方法（包括构造函数、静态方法、实例方法）上方必须包含以下格式的注释块：

```powershell
class ClassName
{
    <#
    .SYNOPSIS
        [简要描述方法功能]
    .DESCRIPTION
        [详细解释方法的工作原理、参数及返回值]
    .PARAMETER [参数名]
        (类型) [该参数的作用及说明]
    .EXAMPLE
        [具体的方法调用示例]
    .OUTPUTS
        [输出对象类型]
    .NOTES
        Author:  lucas_gold
        Website: https://github.com/1274248407
    #>
    [ReturnType] MethodName([Type]$ParamName)
    {
        # 方法实现...
    }
}
```

## 6. 代码注释规范

- **简体中文强制**：所有代码注释（包括单行注释 `#` 和多行注释 `<#...#>`）必须使用简体中文。
  - 函数帮助块的所有内容（.SYNOPSIS、.DESCRIPTION、.PARAMETER 等）必须使用简体中文。
  - 代码中的解释性注释必须使用简体中文。
  - 变量、函数名、参数名等标识符保持英文不变。
- **单行注释强制要求**：以下代码结构前必须添加单行注释说明其用途：
  - 变量声明（尤其是复杂表达式或计算结果）
  - 条件判断（`if`、`switch`）
  - 循环结构（`for`、`foreach`、`while`、`do`）
  - 异常处理块（`try-catch`）
  - 示例：

    ```powershell
    # 构建输出文件路径
    $OutputPath = Join-Path $TmpDir 'output.txt'

    # 检查环境是否满足要求
    if (-not (Test-Path $PythonPath))
    {
        throw "Python 环境不存在"
    }

    # 遍历所有待处理文件
    foreach ($File in $Files)
    {
        # 处理单个文件
        Process-File -Path $File
    }
    ```

## 7. 测试框架规范（Pester v5 - 单元测试与集成测试）

### 7.0 版本要求

- **强制版本**：必须使用 **Pester v5** 版本（v5.3.0 及以上）。
- **版本声明**：测试文件开头应使用 `#Requires -Modules Pester` 声明依赖。
- **兼容性**：禁止使用 Pester v4 及更早版本的语法（如 `Should Be` 需改为 `Should -Be`）。

### 7.1 文件命名规范

- **测试文件命名**：测试文件必须以 `.Tests.ps1` 结尾。
- **文件路径结构**：测试文件应放置在项目根目录下的 `tests` 目录中：
  - 单元测试：`tests/Unit/Public/*.Unit.Tests.ps1`
  - 集成测试：`tests/Integration/*.Integration.Tests.ps1`
- **命名模式**：`{ModuleName}_{FunctionName}.{Scope}.Tests.ps1`
  - 单元测试示例：`IPAP_Get-ImageInfo.Unit.Tests.ps1`
  - 集成测试示例：`IPAP_Rename-FilesBySize.Integration.Tests.ps1`

### 7.2 测试结构规范

- **Describe 块**：用于组织相关测试，描述被测功能模块。
- **Context 块**：用于分组测试场景，描述特定条件下的行为。
- **It 块**：单个测试用例，描述具体的测试断言。
- **BeforeAll/AfterAll**：在所有测试前后执行，用于模块导入和清理。
- **BeforeEach/AfterEach**：在每个测试前后执行，用于测试隔离和清理。

### 7.3 单元测试规范

- **测试范围**：测试单个函数或方法的独立功能。
- **隔离要求**：完全隔离外部依赖，使用 Mock 替代。
- **目的**：验证函数的逻辑正确性，确保每个单元按预期工作。

### 7.4 集成测试规范

- **测试范围**：验证多个函数协作及真实文件系统行为（如目录创建、文件重命名）。
- **隔离要求**：使用 Pester 的 `TestDrive` 动态生成测试文件，禁止依赖仓库内静态夹具，测试结束自动清理。
- **日志屏蔽**：使用 Mock 屏蔽模块日志输出（如 `Write-InfoLog`），避免污染测试输出。
- **数量控制**：仅覆盖核心工作流的正向路径与关键失败路径，不为每个函数编写集成测试。

### 7.5 Mock 规范

- **优先使用 TestDrive**：对于文件操作测试，优先使用 Pester 的 `TestDrive` 功能进行真实文件操作，而非 Mock。
- **只 Mock 外部依赖**：仅 Mock 模块外部的依赖（如系统命令、外部服务调用），不 Mock 模块内部函数。
- **Mock 应在 BeforeEach 中定义**：每个测试前重新定义 Mock，避免测试间的状态污染。
- **避免过度 Mock**：不要为了测试而过度 Mock，保持测试的真实性和可靠性。
- **使用 -ModuleName 参数**：当需要 Mock 模块内调用的命令时，必须使用 `-ModuleName` 参数指定目标模块。

### 7.6 断言规范

- **使用精确断言**：断言应尽可能精确，避免模糊匹配导致的误报。
- **避免简单字符串匹配**：对于内容验证，应使用完整行格式匹配，而非单独的关键字或数字。
  - 不好：`$content | Should -Match '\[X\]'`
  - 好：`$content | Should -Match '- 原始文件是否需要高清化: \[X\]'`
- **使用适当的断言方法**：根据测试场景选择合适的断言方法（如 `-Be`, `-Match`, `-Exist` 等）。

### 7.7 测试隔离规范

- **使用 TestDrive**：文件操作测试必须使用 `TestDrive` 进行隔离，避免影响真实文件系统。
- **清理测试数据**：在 `AfterEach` 或 `AfterAll` 中清理测试产生的数据和状态。
- **避免共享状态**：测试之间不应共享状态，每个测试应独立运行。
