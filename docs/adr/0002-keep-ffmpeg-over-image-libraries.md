# 继续用 ffmpeg + ffprobe，不换成图像处理库或其它二进制

**Status**: accepted（2026-11-18）

## 背景

打包方案定为「一个 zip 全带 bin」，包体约 246 MB，其中 `ffmpeg.exe` 97.3 MB + `ffprobe.exe` 97.1 MB
合计 194.3 MB，占 79%。需要回答：有没有体积更小、又能覆盖现有功能的库或可执行文件。

项目实际只用它们做四件事：

| 用途 | 现在的实现 |
|---|---|
| 读图片宽高 | `ffprobe -show_entries stream=width,height` |
| 算 YDIF（画面细节量） | `ffmpeg -vf format=gray,edgedetect` 输出 PNG，取文件字节数 |
| 转码 webp | `ffmpeg -c:v libwebp -quality 95` |
| Level 1 放大锐化 | `ffmpeg scale=iw*1.2 + unsharp` |

## 决策

维持 ffmpeg + ffprobe，`bin` 随包分发。

## 考虑过的替代方案

| 方案 | 体积 | 覆盖能力 | 否决理由 |
|---|---:|---|---|
| **ImageSharp 4.x** | ~2 MB（纯托管） | 读尺寸、`DetectEdges`(Sobel)、Resize/Sharpen、WebP 编解码，四件事全覆盖 | YDIF 语义改变，阈值需重标定；托管编码远慢于 libwebp；3.x 起为 Six Labors 分拆许可 |
| **SkiaSharp** | 十几 MB 级（按 RID 分发原生库） | 读尺寸、Resize、WebP 编解码；**无边缘检测**，需自写卷积 | 同样改 YDIF 语义；多 RID 原生库 |
| **Magick.NET-Q8** | NuGet 包 97.25 MB（AnyCPU） | 全功能 | 体积几乎没有收益，原生库加载更复杂 |
| **ImageMagick / GraphicsMagick / libvips 的 exe** | 数十 MB 级 | 全功能 | 同上：换二进制即换边缘检测实现，YDIF 全部作废 |
| **去掉 ffprobe，尺寸从 `ffmpeg -i` 的 stderr 解析** | 省 97 MB | 覆盖 | 依赖 stderr 文本格式，跨版本脆弱 |
| **定制精简 ffmpeg 构建** | 预计 20–40 MB | 覆盖 | 要自己编译并托管二进制，维护成本高 |
| **同版本 ffmpeg 的 shared 构建** | zip 77.9 MB / 展开 175.8 MB（含 ffplay） | 完全等价 | **未否决**，见「影响」 |

否决的决定性理由：**YDIF 的定义绑死在 ffmpeg 的 `edgedetect` 上**。它之所以是「边缘图 PNG 的字节数」，
就是因为直接复用了该滤镜的输出。换任何实现，数值分布都会变化，`[classifier] high_detail/medium_detail`
与真实项目上的标定全部作废——这不是多写代码能解决的，要重新标定并回归。

次要理由：libwebp 是 C + SIMD，ImageSharp 是托管实现（其 VP8 编码器有已知高内存分配问题）；
真实项目 1361 页转码现在 102 秒，换库后大概率以分钟计。

## 影响

- 包体维持约 246 MB；作者本人使用，可接受。
- **若将来必须减体积，优先换 shared 构建（同一工具，不换实现）**。2026-11-18 实测
  `ffmpeg-master-latest-win64-lgpl-shared.zip`：
  - zip 77.9 MB（静态 gpl 构建为 192.5 MB），展开后 bin 175.8 MB，删掉不需要的 `ffplay.exe`（23.4 MB）后 152.4 MB；
  - `libwebp` 编码器存在；
  - `edgedetect` 输出的**原始灰度像素与当前构建逐字节相同**（同一张图 SHA256 一致）；
  - 但 YDIF 取的是 PNG **字节数**：旧 241,120 vs 新 248,179（+2.9%），差异来自 PNG 编码器版本而非滤镜；
  - webp 转码 419,722 vs 419,732 字节（+10 字节），放大锐化 688,564 vs 685,690（−0.4%）。
  - 因此换构建前需要：优先找与当前 commit 同日的构建；否则需在真实项目上复测分级分布，
    确认 3% 的 YDIF 漂移不改变任何页面的等级。
- 换库的结论不随「包变大」而改变；要重新评估，必须先拿出重新标定后的分类器实测数据。

## 后续（2026-11-18 已执行）

确定打包带 bin 之后，「维持静态构建」被重新评估：**同工具、同滤镜的 shared 构建**可以在不改变
任何功能的前提下把体积减半，因此已切换到
`bin/ffmpeg-N-129000-g64f6bcffaf-20261117-lgpl-shared`。

- 下载 zip 77.9 MB；解压后只保留 `ffmpeg.exe`、`ffprobe.exe` 与 9 个 DLL，去掉 `ffplay.exe` 后 **152.4 MB**；
- 用 1361 页真实项目复测分级：有文字图 729/2/0、无文字图 629/1/0，**与旧构建逐页一致，0 页翻转**；
  YDIF 平均 +3.18%（0.38%–5.49%）与 +3.44%（0.38%–4.67%），没有页面跨越阈值；
- 包 zip 预计从约 237 MB 降到约 111 MB（ffmpeg 部分 192.5 → 66.4，Real-CUGAN 43.9 不变）；
- 冒烟 28 条、全量测试 721 条通过。

「不换图像库」的结论不变——这次换的是同一工具的链接方式，不是实现。
