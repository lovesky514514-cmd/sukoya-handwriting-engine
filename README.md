# 手写版转化器

直接下载一键包
```text
handwriting-main.zip
```

## 网页预览效果

![网页预览效果](docs/web-preview.png)

## 手写生成效果

![手写生成效果](docs/handwriting-preview.jpg)

> **Sukoyaちゃん · Handwriting Engine**  
> 一个本地运行的手写版转化工具：上传/粘贴题目 → 生成答案 → 编辑答案 → 转成手写版 → 导出 PDF。

## 技术实现

本项目采用 **Vue 前端 + FastAPI 后端 + DeepSeek API + Pillow 图像渲染** 的本地化架构，实现从题目输入、AI 生成答案、人工编辑，到手写版图片 / PDF 导出的完整流程。

---

### 1. 整体架构

项目分为前端、后端、字体资源、手写样本和示例文件几部分：

```text
frontend/                        前端界面，负责题目输入、答案编辑、参数控制和预览展示
backend/                         后端服务，负责文件解析、DeepSeek 调用、手写渲染和 PDF 导出
ttf_files/                       本地字体目录，用于放置 sukoya.ttf / seuomi.ttf
my_handwriting_samples_pdf/       手写样本目录
examples/                        演示测试文本
docs/                            README 预览图
START.bat                        Windows 一键启动脚本
```

整体流程如下：

```text
题目输入 / 文件上传
→ 文本提取
→ DeepSeek 生成答案
→ 用户编辑答案
→ 公式与文本清洗
→ 手写渲染
→ 可选插入图示
→ 生成预览图 / PDF
```

前端负责交互和参数配置，后端负责 AI 调用、文本处理、手写渲染和文件导出。

---

### 2. 前端实现

前端使用 **Vue** 构建单页应用，主要负责题目输入、答案预览、参数控制和结果展示。

主要功能包括：

- 上传 PDF / Word / 图片
- 直接粘贴题目文本
- 调用后端接口生成答案
- 展示答案预览
- 支持人工编辑答案
- 点击“结束更改”后使用最终文本生成手写版
- 控制书写体、混乱度、晕染次数和是否插入图示
- 展示图示预览和手写预览
- 导出 PDF / PNG / SVG

界面采用三栏布局：

```text
左侧：题目输入区
中间：答案预览 / 图示预览 / 手写预览
右侧：功能按钮与参数控制
```

为了适配长题目和长答案，题目区、预览区、功能栏都做了独立滚动处理，避免页面整体布局被撑乱。

---

### 3. 后端实现

后端使用 **FastAPI** 提供本地接口，负责 AI 调用、文件处理、字体读取、手写渲染和 PDF 导出。

主要接口包括：

```text
/api/fonts_info              获取可用字体列表
/api/upload_font             上传个人字体
/api/deepseek_save_key       本次运行中接入 DeepSeek Key
/api/deepseek_polish         调用 DeepSeek 整理答案
/api/generate_handwriting    生成手写预览或 PDF
```

DeepSeek Key 只在运行时使用，不提交到 GitHub。项目通过 `.gitignore` 忽略 `.env`、日志、缓存和临时文件，避免误提交敏感信息。

---

### 4. AI 答案生成

AI 生成部分由 **DeepSeek API** 完成。前端将题目文本和任务类型发送给后端，后端构造提示词，要求模型输出适合手写作业的答案。

生成要求包括：

- 答案简短
- 保留必要步骤
- 不写论文腔
- 避免 Markdown 表格
- 避免复杂 LaTeX 源码
- 保留分数、负号、根号、上下标和箭头
- 多题保持原题号顺序

生成后的答案不会直接进入最终手写版，而是先进入答案预览区。用户可以点击“编辑答案”进行修改，点击“结束更改”后，系统使用最终修改后的内容生成手写版。

---

### 5. 公式与文本清洗

为了避免 AI 输出中出现不适合手写的源码格式，项目加入了公式与文本清洗逻辑。

常见清洗规则如下：

```text
cdot                  → x
times                 → x
neq                   → ≠
leq / geq             → ≤ / ≥
begincases / endcases → 普通分行方程组
```

同时会压缩或删除部分 AI 味表达，例如：

```text
检查：
确实
无交点？检查
综上所述
```

这样可以让最终答案更接近普通学生手写作业的表达方式。

---

### 6. 手写渲染

手写渲染基于 **Pillow** 和字体文件完成。系统会读取当前选择的字体，例如：

```text
sukoya.ttf
seuomi.ttf
```

然后将最终答案逐字渲染到模拟作业纸上。

为了避免生成结果过于机械，项目加入了手写扰动机制：

- 字号轻微变化
- 字间距轻微变化
- 基线轻微上下浮动
- 字符角度轻微变化
- 页面后半部分略微压缩
- 数字、符号、负号、标点单独处理

其中负号和标点符号做了特殊纵向修正，避免出现符号上漂或下沉过度的问题。

---

### 7. 混乱度与晕染次数

项目提供两个手写风格参数：

```text
混乱度：控制字形、间距、角度和基线的随机程度
晕染次数：控制中性笔墨迹的加重程度
```

混乱度示例：

```text
0    更工整
60   自然
100  偏乱
```

晕染次数示例：

```text
0  干净
1  轻微晕染
2  中等晕染
3  明显晕染
```

默认晕染次数为 `0`，避免生成结果过黑。只有用户主动调高时，才会增加轻微墨迹扩散效果。

---

### 8. 书写体档案隔离

项目支持多套书写体档案，目前包括：

```text
sukoya
seuomi
```

两套书写体互相隔离，不会互相覆盖。

对应字体文件：

```text
ttf_files/sukoya.ttf
ttf_files/seuomi.ttf
```

对应样本目录：

```text
my_handwriting_samples_pdf/sukoya/
my_handwriting_samples_pdf/seuomi/
```

如果选择 `sukoya`，系统优先使用 `sukoya.ttf`。

如果选择 `seuomi`，系统优先使用 `seuomi.ttf`。

如果暂时没有 `seuomi.ttf`，也可以先保留 seuomi 样本档案，不会污染 sukoya 字体。

---

### 9. 图示生成与插入

项目支持生成简洁图示，例如函数图像、坐标轴、曲线、圆和箭头等。

图示处理流程如下：

```text
题目文本
→ 识别图示需求
→ 生成 SVG 图示
→ 可选导出 SVG / PNG
→ 可选插入手写答案
→ 自动放在正文下方
```

图示背景为透明，插入手写版时不会遮挡作业纸横线。

如果当前页空间不足，系统会自动分页。

---

### 10. PDF 导出

手写预览图生成后，后端会将页面图像合成为 PDF。

PDF 导出流程如下：

```text
最终答案文本
→ 手写渲染为图片
→ 可选插入图示
→ 分页处理
→ 合成为 PDF
→ 返回前端下载
```

导出的 PDF 可以直接作为项目演示结果或 README 预览素材。

---

### 11. 本地运行与隐私

项目设计为本地运行，不依赖外部服务器。
该项目适合个人学习、作业排版、项目展示和本地 Demo 使用。

## 项目亮点

- 支持 PDF / Word / 图片上传，也支持直接粘贴题目
- DeepSeek 生成答案，支持整理公式、补步骤、改得像手写
- 生成后的答案可以人工编辑，点击“结束更改”后再生成手写版
- 支持 `sukoya` / `seuomi` 两套书写体档案
- 支持混乱度调节：工整 / 自然 / 偏乱
- 支持晕染次数调节：干净 / 轻微 / 中等 / 明显
- 支持图示生成，可选择是否插入手写答案下方
- 支持手写预览图与 PDF 导出
- DeepSeek Key 运行时填写，不写进仓库

## 快速启动

Windows：

```bat
START.bat
```

启动后打开浏览器，填写 DeepSeek API Key 即可使用。

## 字体说明

GitHub 包不内置字体文件。  
本地使用时，把自己的字体放入：

```text
ttf_files/sukoya.ttf
ttf_files/seuomi.ttf
```

如果没有字体文件，程序会临时使用本机系统中文字体兜底。

## 目录结构

```text
backend/                         后端 FastAPI
frontend/                        前端 Vue
ttf_files/                       本地字体目录
my_handwriting_samples_pdf/       手写样本目录
examples/demo_input_all_features.txt  全功能测试文本
docs/web-preview.png             网页预览图
docs/handwriting-preview.jpg     手写效果图
START.bat                        Windows 一键启动
```
