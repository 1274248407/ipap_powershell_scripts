# IPAP 快速开始

把一批原始漫画图片整理成可翻译、可嵌字的项目目录，并在需要时做高清化。

## 环境要求

- Windows 10 / 11
- PowerShell 7.0 或更高（`pwsh`，不是系统自带的 `powershell`）
- 可选：支持 Vulkan 的 GPU（只有 Level 2 页面需要 Real-CUGAN，没有也能跑）

## 三步跑起来

1. 把 zip 解压到任意目录（路径尽量不含 `[ ]` 这类特殊字符）。
2. 在解压目录打开终端，运行：

   ```powershell
   pwsh -File .\Main.ps1
   ```

   首次运行会自动生成 `config.toml`（从 `config.toml.example` 复制），并提示缺少必填项。
3. 按提示填写 `config.toml` 后再次运行。

## config.toml 至少要填这些

```toml
[paths]
# 项目产出的存放目录
base_project_dir = "D:/documents/translation/01_Projects_Active"
# 待处理的原始图片目录
source_dir = "D:/documents/translation/04_Temp/某本漫画"

[project]
author = "作者名"
original_title = "原作品名"
chinese_title = "中文译名"
original_overview = """原文简介"""
chinese_overview = """中文简介"""
```

`[paths]` 里的 `ffmpeg_exe` / `ffprobe_exe` / `realcugan_exe` 已经指向包内 `bin/`，不用改。

> 注意：`[project]` 是全局单例，处理另一本书时要手动改这五项，否则项目目录名和 README 会沿用上一本。

## 运行中会被问什么

1. **无文字图来源**：跨页、纯画格这类没有待翻译文字的图片怎么指定
   - `输入起始编号`：从第 N 张开始都是无文字图
   - `选择子文件夹`：图片按有无文字分开放时用这个
   - `输入自定义路径`
   - `跳过`：全部按有文字图处理
2. **是否应用当前配置**：输入 `Y` 继续。

## 可选：自动补全中文译名 / 简介

`config.toml` 的 `[ai]` 段默认留空，也就是**不启用**。想让工具在缺中文时自动翻译：

1. 填 `endpoint`（OpenAI 兼容的 chat completions 地址，例如 `https://api.deepseek.com/v1/chat/completions`）和 `model`
2. 设置密钥环境变量（变量名由 `api_key_env` 决定，默认 `IPAP_AI_API_KEY`）：

```powershell
$env:IPAP_AI_API_KEY = '你的密钥'
```

补全发生在**配置预览之前**，所以预览里看到的就是补好的中文。

- 触发条件：中文译名/简介为 空、仍是模板占位符（`中文译名` 之类）、与原文相同、或根本不是中文（整句日文、纯英文）
- 方括号里的作者名**不会送进模型**：只翻译正文，译完再原样拼回前缀，作者名一个字符都不经过 AI
- 结果**只对本次运行生效，不写回 `config.toml`**（配置文件是你手写的，写回会毁掉注释）；想固化就自己复制进去
- 没配 key、超时、返回异常都只记日志并保持原值，**不中断流程**

## 产物在哪里

```
<base_project_dir>/<日期>_[作者] 作品名/
├── README.toml                    项目记录（等级、张数、进度、笔记）+ 运行状态
├── 02_Preprocessing/
│   ├── 有文字图转码/放大后的 webp（下游从这里读）
│   ├── original_non_text_raw/     无文字图的处理产物
│   └── raw_source/                有文字图原图备份
└── 03_Typesetting/                后续嵌字用
```

`README.toml` 是 TOML 格式（编辑器会语法高亮）。里面分两类内容：

- **自动段**（`[meta]` `[run]` `[summary]` `[level]` `[outliers]`）：每次运行按最新结果重写，不用手改
- **手工段**（`[progress]` `[notes]` `[todo]` `[misc]`）：进度勾选、处理笔记、待办，**重新运行会原样保留**

`[run].status` 是 `"running"` 说明上次没跑完，下次启动会自动续跑；正常收尾后会变成 `"done"`。

> 从 v2.3.0 起项目记录改为 `README.toml`。老项目里的 `README.md` 不会被删除，但也**不会再更新**——
> 想把之前写在里面的笔记留下来，手动搬到 `README.toml` 的 `[notes]` / `[todo]` 段即可。

同一项目内所有页面使用同一个处理等级（Level 0 只转码、Level 1 用 FFmpeg 1.2 倍锐化、
Level 2 用 Real-CUGAN 超分），保证输出宽高一致。

## 升级

覆盖 `IPAP/`、`bin/`、`README.md` 即可，**保留 `config.toml`**。
新版不会再生成或覆盖配置文件。

## 常见问题

| 现象 | 原因与处理 |
|---|---|
| 提示「未找到 FFmpeg」 | `bin/ffmpeg-*-shared/bin/` 下的 DLL 没解压全；shared 构建必须连 DLL 一起用 |
| 提示「未找到 Real-CUGAN」 | `bin/` 里没有 Real-CUGAN 目录。不影响 Level 0/1，只是 Level 2 页面会被跳过并告警 |
| 输出校验未通过、退出码非零 | 有页面转码失败，已把原图复制到目标目录。查看日志里的「图片处理失败」与「输出格式不符合预期」；**修好源文件后直接重新运行即可，会自动续跑，只补失败的那几页** |
| 想换 ffmpeg 版本 | 替换 `bin/ffmpeg-*-shared` 后同步改 `config.toml` 的两个路径；不同版本会让 YDIF 有约 3% 漂移，换完建议先在一个项目上复测分级 |
