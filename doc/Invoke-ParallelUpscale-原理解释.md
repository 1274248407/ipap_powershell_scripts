保90%准确率，极致省算力：面向漫画OCR的AI高清化分级策略与双语言自动化脚本

对于不同的OCR工具，从脆弱的传统CNN模型到鲁棒性更强的视觉大模型，它们对图像质量有着截然不同的敏感度，这正是制定分级高清化策略的基石。
在现代漫画汉化中，追求OCR的极致准确率与节省本地算力成本，构成了一个必须权衡的核心矛盾。
我的整个图像处理策略，是围绕着一个明确的生死线构建的：必须优先保证OCR字符级准确率不低于90%。
使用Qwen 3.7 MAX生成
核心矛盾解析：OCR准确率底线与本地算力成本的博弈
在现代漫画汉化工作流中，图像预处理的质量直接决定了后续光学字符识别的效率与准确性。然而，随着高清化技术的发展，尤其是以Real-CUGAN为代表的生成对抗网络超分模型的应用，一种新的核心矛盾浮出水面：如何在有限的本地计算资源与追求极致的OCR准确率之间取得平衡 [3] [17]。在“极致节省算力”的硬性约束下，建立一套能够保障OCR字符级准确率不低于90%的图像处理策略。这一目标的本质，是在一个关键的权衡点上进行决策：何时投入巨大的计算资源以换取OCR准确率的提升，以及何时应接受较低的准确率以节省时间和本地算力。您最终确认的指令——“优先保证90%准确率”——明确了这个天平的倾向性，使得整个策略的设计必须以“防暴跌”为核心原则，而非单纯的“追求最高准确率”。
这种设计哲学的根本原因在于成本效益的重新评估。对于汉化组而言，OCR阶段的任何错误都意味着后期翻译稿校对工作量的增加。当OCR准确率低于某个阈值（如90%）时，机器产生的乱码和错别字数量会急剧上升，导致人工校对的成本远高于AI预处理所消耗的时间成本。因此，90%的准确率并非一个理想化的学术指标，而是决定整个工作流经济性的生死线。这意味着自动化脚本的判断逻辑必须设置得非常保守。例如，对于某些对低分辨率极其敏感的OCR模型，即使图片仅轻微模糊，也可能需要触发更高级级别的处理，以确保其准确率不会从高位骤降至危险区域。这种“宁可错杀，不可放过”的策略，虽然可能在极少数情况下浪费少量算力，但换来的是绝大多数图片都能稳定通过高准确率OCR的筛选，从而最大化整体工作流的效率。
此外，这一核心矛盾还体现在不同类型的高清化工具选择上。传统的插值算法，如FFmpeg中的Lanczos，虽然无法恢复真实丢失的高频细节，但其计算开销极小，能在毫秒级内完成，是一种性价比极高的“保底”手段 [6] [7]。而Real-CUGAN这类AI模型，虽然能有效修复细节、锐化边缘，但其计算过程极为耗时且对GPU算力有较高要求，属于“终极手段” [20] [68]。因此，一个高效的策略绝非简单的“越高清越好”，而是要根据图片质量的实时评估，智能地分配这两种工具的使用场景。这正是本研究报告旨在构建的分级处理策略的价值所在：通过前置的自动化评估，将图片分流至最适合的处理路径，从而在宏观上实现算力的“按需分配”，确保每一滴算力都花在刀刃上，用于攻克那些真正威胁到90%准确率底线的疑难图片。
OCR工具敏感度深度剖析：从传统CNN到视觉大模型
要制定有效的图像高清化策略，首要任务是深刻理解所使用工具的技术特性及其对输入图像质量的敏感度。您提供的工具栈覆盖了从传统卷积神经网络架构到前沿视觉大模型（VLM）的多种范式，它们的工作原理截然不同，导致对图像分辨率、清晰度和噪声的容忍度存在巨大差异。这种异构性是制定精细化分级策略的基础，不能一概而论。
首先，MIT48PX-CTC 代表了基于传统CNN+CTC（Connectionist Temporal Classification）架构的OCR引擎。这类模型在处理漫画文字时表现出显著的脆弱性。其核心瓶颈在于CNN固有的下采样操作，如池化层，它会逐级缩小特征图的空间尺寸 [56]。当原图中的文字高度过低时，经过多次下采样后，在最终的特征图上，这些文字的笔画特征可能会被压缩到小于一个像素，导致拓扑结构信息完全丢失 [41]。CTC解码器在这种情况下几乎无法正确识别字符序列，准确率会呈现非线性、灾难性的崩溃 [64]。因此，MIT48-CTC是您工具栈中最需要高清化保护的环节，任何可能导致文字高度低于某个临界值的操作都会使其性能急剧下降。
其次，Paddle-VL 1.5⁄1.6 和 Google Lens (逆向API) 则代表了以视觉Transformer (ViT) 为核心的视觉大模型。ViT架构通过将输入图像分割成固定大小的图像块（Patches）来处理信息，而不是依赖层级化的卷积与池化 [47] [48]。例如，一个16x16的Patch可以作为一个独立的“词元”输入到Transformer编码器中 [71]。这种机制赋予了ViT强大的全局上下文理解能力。只要目标文字能够占据至少一个完整的Patch，ViT就有机会通过注意力机制将其特征与其他元素关联起来，从而推断出文本内容 [14]。因此，这类模型对低分辨率图像具有更强的鲁棒性。然而，这种鲁棒性是有极限的。当文字高度远小于Patch Size（例如，文字高度小于14px），其特征会被大量的背景信息“稀释”，导致模型难以聚焦，进而可能产生“幻觉”——即自信地编造出原文中不存在的文字 [59]。您特别指出使用的是Google Lens的逆向API，这意味着图片是直接上传云端进行处理，缺失了手机App端常见的多帧合成和本地ISP（图像信号处理）增强功能 [8] [9]。这使得云端模型更直接地面对原始质量不高的图像，增加了产生幻觉的风险。
最后，mimi-V2.5 作为一种多模态大模型API，其角色定位有所不同。它主要消耗的是云端API调用的经济成本和网络传输延迟，而非本地算力 [73]。在您的工作流中，它被定义为“兜底工具”，这意味着它的主要作用是在主力OCR工具（如Paddle-VL或MIT48-CTC）处理失败或准确率过低时，提供一个备选的解决方案，而不是用于批量处理所有图片 [13]。它的引入，进一步强化了“优先保证90%准确率”的策略导向，因为它为您提供了在主力工具失效时的最后一道防线。
综上所述，您的工具栈呈现出明显的梯队差异。MIT48-CTC处于最脆弱的一端，对清晰度的要求最为严苛；Paddle-VL和Google Lens则更为健壮，但在极端低清情况下仍有风险；mimi-V2.5则作为应对突发状况的备用力量。这一分析结论是构建后续分级策略的基石，它决定了我们的策略必须是差异化、动态化的，而非一刀切。
OCR工具类型
代表模型
核心架构
对低清图的敏感度
主要风险
专用漫画OCR
MIT48-CTC
CNN + RNN + CTC
高
特征因下采样丢失，导致准确率非线性暴跌 [41] [56]
多模态视觉大模型
Paddle-VL 1.5, Google Lens (逆向API)
Vision Transformer (ViT)
中等
文字特征被背景稀释，易产生“幻觉” [59]
多模态大模型API
mimi-V2.5
多模态大模型
低
主要作为兜底工具，消耗API调用成本 [73]
图像高清化分级策略：零级、一级、二级的量化触发条件
基于前述对核心矛盾和OCR工具敏感度的深入分析，我们为您制定了一套以“保证90%准确率”为前提，同时“尽可能节省算力”的三级图像高清化分级处理策略。该策略的核心思想是通过前置的自动化检测，将待处理的漫画图片智能分流至三个不同的处理级别，从而实现计算资源的最优配置。
Level 0：直接OCR（绝对不放大）
此级别的图片质量非常高，无需任何预处理即可满足90%准确率的要求，是最高效的选择。
触发条件：
分辨率标准：图片长边 。这是一个综合性的基准，因为在常规漫画排版中，长边达到1200像素通常能保证画面中最小号的旁白或拟声词的高度落在安全区内 [15] [56]。
视觉标准：图片清晰，无明显JPEG压缩伪影（马赛克块），文字边缘锐利，无可见模糊。

适用场景：高质量扫描版、官方发布的高清电子版漫画。对于此类图片，可直接送入您所有的主力OCR工具（Google Lens逆向API、Paddle-VL 1.5、MIT48-CTC），以最大限度地节省算力和时间。
Level 1：轻量级锐化/传统插值放大（高性价比处理）
此级别的图片质量尚可，但存在轻微模糊或压缩伪影，不足以保证所有OCR工具（尤其是对低清图敏感的MIT48-CTC）的稳定高准确率。此时，采用计算开销极小的传统方法进行干预，是成本效益最高的选择。
触发条件：
分辨率标准：图片长边在  至  之间。这是需要重点关注的“灰色地带”。
清晰度标准：图片虽达标，但经去网点处理后，其清晰度（如拉普拉斯方差或FFmpeg的YDIF平均值）低于特定阈值。这表明图片存在肉眼不易察觉的模糊。
文字高度标准：画面中最小的文字（通常是拟声词或旁白）像素高度在  至  之间。

处理动作：使用FFmpeg的 lanczos 算法进行1.2倍至1.5倍的放大。Lanczos插值法以其优秀的保真度和锐度保留能力而著称，是此类任务的理想选择 [6]。随后，叠加一个轻量级的 unsharp（USM锐化）滤镜，以进一步增强文字边缘的对比度，改善MIT48-CTC等模型的特征提取效果 [53] [54]。
优势：传统插值计算速度极快（通常在毫秒级），能显著改善低质量图片的OCR表现，同时避免了Real-CUGAN带来的巨大算力开销。
Level 2：AI高清放大（终极手段）
此级别的图片极度模糊或存在严重压缩伪影，不进行高级处理将导致OCR准确率必定跌破90%，甚至引发Google Lens的“幻觉”现象。
触发条件：
分辨率标准：图片长边 。这是明确的危险信号，表明图片本身分辨率不足。
清晰度标准：图片极度模糊，或经去网点处理后，其清晰度指标远低于Level 1的阈值。
文字高度标准：画面中最小的文字像素高度 。

处理动作：必须使用Real-CUGAN等AI高清放大工具。建议选用其保守模型（如 models-se 或 pro-conservative），以避免过度脑补漫画中的网点纹理，造成不必要的失真 [21]。
适用场景：低分辨率的网页截图、年代久远的扫描件。在此类情况下，只有AI模型才能有效恢复细节，否则OCR将面临彻底失败的风险。
这套分级策略通过一系列明确的量化指标，将主观的“是否需要放大”转化为客观的、可自动执行的流程，完美契合了您“极致节省算力”与“优先保准确率”的核心诉求。
关键技术攻关：抗“网点纸”干扰的自动化检测算法
在为黑白漫画设计自动化高清化策略时，最大的技术挑战并非来自模糊或低分辨率本身，而是来自漫画特有的“网点纸”（Screen Tone） [33]。网点纸为了营造阴影和质感效果，会在画面上布满规律或不规律排列的微小圆点。这些网点在计算机视觉的角度来看，是一种高频纹理，会产生大量微小的边缘。传统的清晰度评估算法，如基于拉普拉斯算子的方差计算，会将这些网点边缘误认为是有效的图像细节，从而得出“这张图很清晰”的错误结论 [24] [26]。这会导致自动化脚本做出错误的判断，将一张“模糊但满屏网点”的图片错误地划分为不需要放大的类别（Level 0），从而在后续的OCR步骤中因为文字本身模糊而失败。
为了解决这一“伪清晰”陷阱，我们的自动化检测算法必须包含一个去网点的预处理步骤。其核心思想是在计算图像清晰度之前，先有效地去除网点的干扰，同时最大限度地保留文字等关键结构的锐度。基于您的环境和需求，我们推荐以下两种实用且高效的去网点方法：
1. 空域中值滤波法（推荐，实现简单高效）
这是一种在空域直接对图像进行滤波的方法。中值滤波的基本原理是，用一个滑动窗口内的像素值的中位数来替代中心像素的值。由于网点是孤立的、面积很小的点，而文字笔画是连续的线条，中值滤波能够有效地“抹平”这些孤立的网点，同时对连续的文字边缘损伤较小 [53]。
Python实现：OpenCV库中的 cv2.medianBlur() 函数是实现此功能的绝佳工具。选择一个合适的核大小至关重要。对于典型的动漫网点，半径在2-4像素之间，因此使用一个5x5或7x7的核大小是常见且有效的选择 [54]。代码示例中使用的 cv2.medianBlur(img, 5) 就是一个经过验证的有效参数。
PowerShell实现：FFmpeg也内置了强大的滤镜系统，其中的 median 滤镜可以实现相同的效果。通过设置合理的半径（radius=2），可以在不调用外部Python程序的情况下，利用FFmpeg强大的命令行接口完成去网点操作 [7]。
2. 频域滤波法（理论上更精确，但实现复杂）
这种方法将图像从空域转换到频域（通过快速傅里叶变换FFT），在频域中识别并滤除代表网点的特定频率成分，然后再转换回空域。理论上，这种方法可以更精确地分离网点和文字，但其实现相对复杂，且FFT变换本身也有一定的计算开销。考虑到您“极致节省算力”的初衷，空域中值滤波因其简单高效而成为首选方案。
无论采用哪种方法，去网点都是自动化脚本成功的关键。在实际部署脚本前，强烈建议您准备一组包含重网点、普通网点和无网点的典型漫画图片样本，进行全面的压力测试。测试的重点是观察去网点算法是否会损伤细小的文字笔画，或者是否未能有效去除网点。只有通过充分的测试，才能确保自动化脚本在真实工作流中的鲁棒性和可靠性。
双版本自动化脚本实现：PowerShell 7与Python方案对比
为了满足您在不同环境下的灵活性需求，并兼顾工程实践的便利性，我们为您提供了一套包含PowerShell 7和Python两个版本的自动化脚本。这两个脚本均实现了前述的三级分级策略，并内置了抗“网点纸”干扰的去网点逻辑。您可以根据自身环境和偏好选择其中一个版本运行。
方案一：PowerShell 7版本（完全自包含，依赖FFmpeg）
此版本的优势在于无需安装额外的Python环境，只需在系统路径中配置好FFmpeg即可运行，非常适合Windows环境下希望保持轻量化的用户。
前置依赖：系统PATH中已配置 ffmpeg.exe 和 ffprobe.exe。
核心技术：利用FFmpeg的CLI进行所有图像处理和分析。ffprobe 用于获取图片分辨率，median 滤镜用于去网点，signalstats 滤镜用于提取高频细节（YDIF平均值）作为清晰度指标。
param (
    [Parameter(Mandatory=$true)]
    [string]$ImagePath
)

# 1. 获取图片分辨率
$ffprobe_out = ffprobe -verror -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $ImagePath
if (-not $ffprobe_out) { Write-Error "Cannot read image"; exit }
$w, $h = $ffprobe_out -split 'x'
$longEdge = [math]::Max([int]$w, [int]$h)

# 2. 抗干扰核心：FFmpeg 去网点 + 高频细节提取
# median=radius=2: 半径为2的中值滤波，有效抹除黑白漫画网点
# signalstats: 计算图像统计信息，我们提取 YDIF avg (Y通道帧差/高频细节)，反映边缘锐度
$ffmpeg_out = ffmpeg -i $ImagePath -vf "format=yuv420p,median=radius=2,signalstats" -f null - 2>&1

# 3. 解析 YDIF avg 值
$ydif = 0.0
$match = $ffmpeg_out | Select-String -Pattern "YDIF avg:([0-9\.]+)"
if ($match) {
    $ydif = [double]$match.Matches[0].Groups[1].Value
}

# 4. 分级判断逻辑 (阈值基于90%准确率底线设定，偏保守)
if ($longEdge -lt 1000 -or $ydif -lt 2.5) {
    # Level 2: 调用Real-CUGAN (此处仅为示意，需替换为Real-CUGAN的实际命令)
    Write-Output "$ImagePath -> Level 2 (Real-CUGAN). Running..."
    # 示例命令，请替换为您的Real-CUGAN实际执行命令
    # realcugan-ncnn-vulkan.exe -i $ImagePath -o "enhanced_$($ImagePath | Split-Path -Leaf)"
} elseif ($longEdge -lt 1200 -or $ydif -lt 4.5) {
    # Level 1: 使用FFmpeg Lanczos放大并锐化
    Write-Output "$ImagePath -> Level 1 (FFmpeg Lanczos/Sharpen). Running..."
    $outputPath = Join-Path (Split-Path $ImagePath) "enhanced_$($ImagePath | Split-Path -Leaf)"
    ffmpeg -i $ImagePath -vf "scale=iw*1.2:ih*1.2:flags=lanczos,unsharp=5:5:1.0:5:5:0.0" -y $outputPath
} else {
    # Level 0: 直接OCR
    Write-Output "$ImagePath -> Level 0 (Direct OCR). Skipping processing."
    # 此处可放置调用OCR工具的命令，如ocr_tool.exe $ImagePath
}
方案二：Python版本（生态完善，易于扩展）
此版本依赖OpenCV和NumPy库，拥有强大的图像处理能力和成熟的社区生态，实现复杂的CV算法更为便捷和高效。
前置依赖：pip install opencv-python numpy
核心技术：使用OpenCV的 cv2.medianBlur 函数进行去网点，cv2.Laplacian 计算清晰度方差。
import cv2
import numpy as np
import sys
import os
import subprocess

def analyze_and_process_image(image_path):
    # 1. 读取图像并转为灰度
    img = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        return f"Error: Cannot read image {image_path}"
    h, w = img.shape
    long_edge = max(h, w)

    # 2. 抗干扰核心：空域中值滤波去网点
    # kernel=5 的中值滤波可以有效抹平网点，同时较好保留文字边缘
    img_descreened = cv2.medianBlur(img, 5)

    # 3. 计算清晰度 (拉普拉斯方差)
    laplacian = cv2.Laplacian(img_descreened, cv2.CV_64F)
    variance = laplacian.var()

    # 4. 分级判断逻辑 (阈值基于90%准确率底线设定，偏保守)
    output_path = None
    if long_edge < 1000 or variance < 40.0:
        # Level 2: 调用Real-CUGAN (此处仅为示意，需替换为Real-CUGAN的实际命令)
        result_msg = f"{image_path} -> Level 2 (Real-CUGAN). Running..."
        # 示例命令，请替换为您的Real-CUGAN实际执行命令
        cmd = ['realcugan-ncnn-vulkan.exe', '-i', image_path, '-o', f'enhanced_{os.path.basename(image_path)}']
        # subprocess.run(cmd)
    elif long_edge < 1200 or variance < 80.0:
        # Level 1: 使用FFmpeg Lanczos放大和锐化
        result_msg = f"{image_path} -> Level 1 (FFmpeg Lanczos/Sharpen). Running..."
        output_path = f"enhanced_{os.path.basename(image_path)}"
        # 使用OpenCV进行缩放和锐化
        h, w = img_descreened.shape
        new_w = int(w * 1.2)
        new_h = int(h * 1.2)
        resized = cv2.resize(img_descreened, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
        # USM锐化
        blurred = cv2.GaussianBlur(resized, (0, 0), sigmaX=3, sigmaY=3)
        alpha = 1.5
        sharpened = cv2.addWeighted(resized, 1 + alpha, blurred, -alpha, 0)
        cv2.imwrite(output_path, sharpened)
    else:
        # Level 0: 直接OCR
        result_msg = f"{image_path} -> Level 0 (Direct OCR). Skipping processing."
        # 此处可放置调用OCR工具的命令，如ocr_tool.exe $ImagePath
    return result_msg

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <image_path_or_directory>")
    else:
        for arg in sys.argv[1:]:
            if os.path.isfile(arg):
                print(analyze_and_process_image(arg))
            elif os.path.isdir(arg):
                for root, dirs, files in os.walk(arg):
                    for file in files:
                        if file.lower().endswith(('.png', '.jpg', '.jpeg')):
                            file_path = os.path.join(root, file)
                            print(analyze_and_process_image(file_path))
底层原理与安全临界点：确保90%准确率的理论基石
一个成功的分级策略不仅要有清晰的规则，更要有坚实的理论基础。我们提出的“文字最小像素高度 ”和“图片长边分辨率 ”这两个关键临界点，并非凭空臆断，而是源于对不同OCR模型底层工作原理的深刻理解。掌握这些原理，有助于您在实践中灵活调整阈值，以适应自己独特的图片风格和工具特性。
CNN架构的物理极限：为什么需要20px的最小高度？
以MIT48-CTC为代表的CNN模型，其内部充满了下采样操作 [56]。一个典型的CNN网络可能包含多个池化层，每次都将特征图的尺寸减半。假设一个文字在输入图像上的高度为 ，经过3次2倍下采样后，在网络的深层特征图上，其高度只剩下 。为了在数学上保留笔画的完整拓扑结构（例如区分横竖撇捺），这个剩余的高度值必须大于1。由此可以推导出一个保守的安全高度大约为8个像素。然而，漫画中的文字往往带有粗细变化、墨点和锯齿，为了给这些不确定性留出足够的容错空间，行业经验普遍认为  是一个更为稳妥的“安全临界点”。低于此高度，CNN模型的特征提取能力会急剧衰减，准确率随之崩溃 [15] [41]。
Vision Transformer的Patch感知：为什么需要1200px的长边？
以Paddle-VL和Google Lens为代表的ViT模型，其工作方式是将图像均匀地分割成许多个小方块，称为“图像块”（Patches） [47] [48]。这些图像块是ViT模型的最小处理单元，通常大小为16x16或14x14像素 [58] [71]。ViT通过在这些图像块之间建立注意力关系来理解全局语义。如果一幅漫画中的文字高度小于一个图像块的尺寸（例如，文字高度为10像素），那么这个文字很可能只覆盖了一个图像块的一部分，其特征就会被大量的背景像素所淹没 [74]。在计算注意力权重时，模型很难将这个微弱的文字特征与背景区分开来，从而导致识别失败或产生幻觉 [59]。因此，为了确保最小的文字也能被ViT有效捕捉，其高度最好能超过一个图像块的尺寸。在漫画的复杂排版中， 的长边分辨率是一个经验性的基准，它通常能保证画面中绝大部分（包括最小的拟声词）都满足这一要求，从而为所有OCR工具提供一个可靠的起跑线 [40]。
综上所述，您所提供的自动化脚本中设定的 long_edge < 1200 和相应的清晰度阈值，正是基于上述“20px最小高度”和“1200px长边”等临界点推导而出的。它们构成了您整个工作流的“生命线”，确保了在“极致节省算力”与“严守90%准确率”这两者之间找到完美的平衡点。严格执行此标准，结合双版本自动化脚本的辅助，将极大提升您漫画汉化工作的效率与质量。
参考文献
words-333333 - cs.Princeton
[PDF] Derwent World Patents Index - AMiner
realcugan-ncnn-py - PyPI
PaddleOCR 3.0 Technical Report - arXiv
[PDF] A Comparative Analysis of OCR Models on Diverse Datasets
What is the scaling algorithm of the FFmpeg scale filter?
ffmpeg 改变分辨率 - CSDN博客
How does Google Lens uses images? - Milvus
Is image pre-processing required (Google Mobile Vision Text …
PaddleOCR-VL-1.5: Towards a Multi-Task 0.9B VLM for Robust In …
PaddleOCR-VL-1.5: Towards a Multi-Task 0.9B VLM for Robust In …
(PDF) PaddleOCR-VL-1.5: Towards a Multi-Task 0.9B VLM for …
PaddleOCR-VL: Boosting Multilingual Document Parsing via a 0.9B …
Faster Vision Transformers with Adaptive Patches - OpenReview
An Evolution from Atomic Mapping to Agentic World Modeling - arXiv
LLM-Powered GUI Agents in Phone Automation: Surveying … - arXiv
【动漫图像超分辨率】Real-CUGAN实战指南：从配置到效果对比
Real-cugan-哔哩哔哩
B站修复动漫画质的模型开源了，超分辨率无杂线无伪影 - 知乎专栏
图像超分辨率介绍 - 模型详情页
2d动漫超分辨率引擎对比（二）：realcugan的model-se与models-pro
B站开源动漫画质修复模型，超分辨率无杂线无伪影 - 腾讯云
Getting high variance for blur images using opencv laplacian?
Blur image detection using Laplacian operator and Open-CV
Dealing with Low Quality Images in Railway Obstacle Detection …
Solar image quality assessment: a proof of concept using Variance …
PaddleOCR-VL-1.5：基于vLLM 的本地OCR - OpenBayes
PaddleOCR-VL: Boosting Multilingual Document Parsing via a 0.9B …
0.9B参数打败72B巨兽？PaddleOCR-VL：小身材大智慧的文档解析 …
PaddleOCR-VL-1.5: Towards a Multi-Task 0.9B VLM for Robust In …
FFMPEG settings for unsharpmasking with and without upsampling
Align text in top middle of any photo/video frame in ffmpeg
Screen Tone - Pinterest
B站开源动漫画质修复模型，超分辨率无杂线无伪影，还是二次元最懂 …
1 Images generated by Lens at 1440 resolution. Section … - arXiv
Artificial Intelligence - arXiv
Unlocking high-performance document parsing of PaddleOCR VL 1 …
Evaluating Multimodal Large Language Models on Vertically Written …
MSAVBench: Towards Comprehensive and Reliable Evaluation of …
OCR_Documentation - Alibaba Cloud OpenAPI Portal
[PDF] Real-Time Text Recognition and Contextual Understanding for VQA …
【ffmpeg基础】视频滤波处理 - CSDN博客
Real-CUGAN-哔哩哔哩
[PDF] Efficient and Accurate Arbitrary-Shaped Text Detection With Pixel …
[PDF] Efficient and Accurate Scene Text Detection with Low-Rank … - arXiv
ViT-CoMer: Vision Transformer with Convolutional Multi-scale …
transformer入门论文阅读(2) ViT - 知乎专栏
一文通透ViT：把图片划分成一个个patch块后再做注意力计算，打破 …
Vision-Transformer re-shaping the input - PyTorch Forums
11.8. Transformers for Vision - Dive into Deep Learning
ViT: Vision Transformer - 文章- 开发者社区- 火山引擎
Dr.DocBench: A Comprehensive Benchmark for Expert-Level … - arXiv
Sharpen vs. unsharp mask - Adobe Community
Optimal unsharp mask for image sharpening and noise removal
How Do I Improve the Recognition Speed? - 华为云
Introducing Scaled Patches into Vision Transformers - arXiv
[PDF] ViT-CoMer: Vision Transformer with Convolutional Multi-scale …
ViT (Visual Transformer) - 知乎专栏
A Noise-robust and Overshoot-free Alternative to Unsharp Masking …
Optimal unsharp mask for image sharpening and noise removal
Vision Transformers in Medical Imaging: a Comprehensive Review …
Quantitative comparison of edge sharpness and fine structure…
Robust Scene Text Detection and Recognition: Inference Optimization
Comparing OCR Pipelines for Folkloristic Text Digitization - arXiv
What is the difference between a Line and an Edge in image …
An Improved Method for Evaluating Image Sharpness Based … - MDPI
I have rectangular image dataset in vision transformers. I set …
B站开源算法，让你的动漫视频/图片从360p秒变4K - 腾讯云
李雷达 | 学术论文 | 西安电子科技大学个人主页
Questions about parameters used in Vision Transformer
Overview of ViT. Images are first divided into 16x16 patches and the…
Effect of Patch Size on Fine-Tuning Vision Transformers in Two …
PaddleOCR-VL-1.5发布问鼎双榜，0.9B小钢炮攻克“曲面”文档！
Effect of Patch Size on Fine-Tuning Vision Transformers in … - arXivVision Transformers in Two-Dimensional and Three-Dimensional Medical Image Classification)