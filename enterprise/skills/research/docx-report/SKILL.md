---
name: docx-report
description: 生成专业格式的Word文档（.docx）——适用于深度分析报告、投资研究报告、客户画像报告等长文结构化文档。当用户要求"生成Word文档""导出docx""写一份报告并生成word"或涉及.docx输出时触发。使用python-docx库生成带样式（标题层级、表格配色、中文字体）的文档。
version: 1.0.0
category: productivity
tags:
  - docx
  - report-generation
  - python-docx
  - word
  - long-form
triggers:
  - "生成.*word.*文档"
  - "导出.*docx"
  - "写.*报告.*word"
  - "生成.*.docx"
  - "输出.*word"
  - "不少于.*字.*word"
  - "文档.*docx"
  - "深度分析.*生成.*word"
  - "分析.*生成.*报告"
  - "生成.*深度.*报告"
---

# docx-report — Word文档生成技能

## 触发条件

用户要求生成Word文档（.docx）格式的结构化报告时触发。典型场景：
- 深度分析报告（投资、行业、公司研究）
- 客户画像报告
- 风险评估报告
- 尽职调查报告
- 任何"不少于N字"的长文结构化文档

## 核心能力

1. **python-docx生成**：使用`python-docx`库创建带完整样式的Word文档
2. **中文字体支持**：自动设置宋体正文、黑体标题
3. **表格样式**：深蓝表头+交替行底色
4. **结构化章节**：封面→目录→多级标题→表格→风险标注→附录
5. **合规标注**：数据来源、免责声明、时效性声明自动附加

## 工作流

### Step 1：确认输出路径

.docx文件默认输出到workspace的exports子目录，遵循项目文档路由规则。

### Step 2：加载模板

调用 `skill_view(name="docx-report", file_path="templates/report-script.py")` 获取基础脚本模板。

### Step 3：组装内容

将分析结果填充到脚本模板中，遵循以下格式规范：

| 元素 | 规范 |
|------|------|
| 封面标题 | 28pt 黑体 深蓝色 居中 |
| 一级标题 | Word Heading 1 样式 黑体 |
| 二级标题 | Word Heading 2 样式 黑体 |
| 正文 | 11pt 宋体 1.5倍行距 首行缩进2字符 |
| 表格表头 | 9pt 白色加粗 深蓝底色 |
| 表格数据 | 9pt 宋体 奇偶行交替底色 |
| 页边距 | 上下2.5cm 左右2.8cm |

### Step 4：生成并验证

```bash
cd /data/hermes/workspace && python scripts/<脚本名>.py
```

验证：
- 总字符数 ≥ 用户要求
- 表格数、标题数符合预期
- 文件可正常打开

### Step 5：展示点击下载链接（强制）

报告 `.docx` 生成并验证通过后，**除上述展示要求外**，必须在结果对话框中展示 Word 报告的**点击下载链接**，让用户直接点击下载：

```
MEDIA:/data/hermes/workspace/exports/<报告文件名>.docx
```

**空文件防护（强制）**：展示下载链接前，必须先确认 `.docx` 文件非空——用 `ls -lh` 或 `wc -c` 检查文件大小，确认 > 0 字节。若文件为 0 字节或生成失败，**不得**展示下载链接，须如实报告转换失败原因，绝不能让用户点击下载到空文件。

## 关键原则

### 内容质量
- **不编造数据**：所有财务数据必须标注来源和置信度
- **区分事实与推测**：推算数据用 `[推导估算值，置信度：高/中/低]` 标注
- **免责声明**：每份报告必须包含免责声明

### 格式质量
- **表格配色一致**：深蓝表头 + 交替行底色
- **中文字体正确**：正文宋体、标题黑体
- **不过度装饰**：避免AI生成的典型特征（标题下划线、过度图标等）

### 数据标注规范
```
确定数据 → 直接引用，标注来源
推算数据 → 标注"[推导估算值，基于XX模型，置信度：高/中/低]"
未知数据 → 标注"公开信息未披露"
```

### 图表嵌入（matplotlib → python-docx）

当报告需要嵌入数据图表时，按以下模式操作：

1. **先生成图表PNG**：用matplotlib编写独立图表脚本，输出到 `artifacts/` 目录
2. **再嵌入Word**：在docx生成脚本中用 `doc.add_picture(path, width=Inches(5.3))` 嵌入
3. **图表编号和标题**：使用 `add_chart()` 辅助函数，自动处理居中+标题

⚠️ **matplotlib中文字体坑**：Linux环境通常缺少中文字体。解决方案：
```python
# 下载SimHei.ttf到 ~/.fonts/
# 然后在图表脚本中:
import matplotlib.font_manager as fm
font_path = os.path.expanduser('~/.fonts/SimHei.ttf')
fm.fontManager.addfont(font_path)
plt.rcParams['font.sans-serif'] = ['SimHei']
plt.rcParams['axes.unicode_minus'] = False
# 清除旧缓存: rm -rf ~/.cache/matplotlib
```

### 多视角分析框架（可选模块）

对于深度金融/企业分析报告，可启用以下分析视角模块：

| 视角 | 核心方法 | 适用场景 |
|------|---------|---------|
| **经济师视角** | 宏观经济学供需框架、产业组织理论（波特五力）、战略经济学 | 行业赛道分析、企业战略定位 |
| **审计师视角** | 财务报表穿透分析（收入确认/应收/研发资本化/现金流）、KAM识别 | 盈利质量检验、风险甄别 |
| **SPoF分析** | 单点失效链推演（触发条件→传导路径→崩溃概率） | 尾部风险压力测试 |
| **SOTP估值** | 分部估值法（AI业务PS + 传统业务PE + 期权价值） | 多业务线公司估值 |

### 字数验证

生成后必须验证字数：
```python
from docx import Document
doc = Document(path)
total = sum(len(p.text) for p in doc.paragraphs)
for t in doc.tables:
    for row in t.rows:
        for cell in row.cells:
            total += len(cell.text)
print(f'字符数: {total}')
# 不满足字数要求则追加内容后重新生成
```

## 依赖

需要 `python-docx` Python包。如未安装，运行 `pip install python-docx`。
如需图表，额外需要 `matplotlib numpy`，运行 `pip install matplotlib numpy`。

## 长篇报告（≥20,000字）的模块化写法

当报告超过20,000字时，**禁止写单个巨型.py文件**（会触发lint超时和小文件保护）。必须拆分为：

1. **N个内容模块文件**（如 `content_a.py`, `content_b.py` ...），每个约7,000-10,000字
   - 每个模块内部构建一个 `C = []` 列表，元素为元组：`('h1', text)`, `('h2', text)`, `('p', text, bold)`, `('table', headers, rows)`, `('pb',)`
   - 每个模块文件末尾暴露：`CONTENT = C`（或直接写 `C`，由主脚本通过 `importlib.util` 加载）
   - 模块内不 import docx，仅定义数据，保持纯数据文件

2. **一个主构建脚本**（如 `build_report.py`）
   - import 所有内容模块，拼接 `CONTENT` 列表
   - 初始化 `Document()`、设置样式、生成封面和目录
   - 遍历拼接后的 `CONTENT`，按元组类型调用对应的 add 函数
   - 保存后跑字数验证

3. **关键代码模式**：
```python
# 主脚本中加载数据模块
import importlib.util
def load_content_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.CONTENT  # 或 m.C
```

4. **各模块文件相互独立**，不互相 import；所有需要的数据（如日期字符串）可在主脚本中传递或直接硬编码在各模块中。

5. **字数控制**：主构建脚本末尾必须运行字符数统计，若未达用户要求则追加模块或补充章节。

详见 `references/long-report-modular-pattern.md`。

## 支持文件

- `templates/report-script.py` — 基础python-docx报告生成脚本模板
- `references/chart-to-docx-pipeline.md` — matplotlib图表生成→python-docx嵌入的完整流水线指南（含中文字体安装、图表类型速查、常见坑）
- `references/long-report-modular-pattern.md` — 长篇报告（≥20,000字）的模块化拆解与构建模式
- `references/report-delivery-convention.md` — 报告输出统一交付规范（跨 skill 约定）：点击下载链接 + 空文件防护，附 11 个已覆盖 skill 清单、跳过清单、验证方法
