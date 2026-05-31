---
alwaysApply: true
---
# PowerShell 7 专项开发规则

## 1. 语法与架构硬性约束
- **强类型契约**：禁止使用弱类型定义。必须为所有变量、函数参数（param 块）及返回值显式标注类型。
  - 示例：`[string]$UserName = "Lucas"`, `[int]$RetryCount = 3`
- **标准架构**：所有函数必须包含 `[CmdletBinding()]` 属性，并统一使用 `param()` 块定义参数。

## 2. 命名与风格规范
- **PascalCase 强制化**：所有自定义变量名、函数名、参数名必须使用 PascalCase（大驼峰命名法）。
  - *例外情况*：系统内置自动变量（如 `$PSBoundParameters`, `$PSItem`, `$args`, `$foreach`, `$HOME` 等）保持原样，不强制执行。
- **$PSItem 强制化**：禁止使用 `$_`，必须使用 `$PSItem` 以提高可读性。
  - 适用于所有场景：`ForEach-Object`、`Where-Object`、`switch` 语句、管道脚本块等。
- **重构指令**：在修改或重构现有代码时，AI 必须主动修复不符合 PascalCase 规范或缺失类型声明的旧代码块。

## 3. 防御性编程 (Error Handling)
- **风险驱动的 Try-Catch**：
  - 凡涉及 **IO 操作**（文件读取、写入、移动等）的逻辑，必须包裹在 `try-catch` 结构中。
  - 凡涉及 **网络请求**（如 `Invoke-RestMethod`, `Invoke-WebRequest`）的逻辑，必须包裹在 `try-catch` 结构中。
  - `catch` 块应包含明确的异常处理逻辑（如 `throw $PSItem`）。

## 4. 强制 Help-Based Help 模板
每个定义的函数上方必须包含以下格式的注释块，作者信息固定如下：

```powershell
<#
.SYNOPSIS
    [简要描述函数功能]
.DESCRIPTION
    [详细解释函数的工作原理、逻辑及适用场景]
.PARAMETER [参数名]
    [该参数的作用及说明]
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
## 5. 代码注释规范
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