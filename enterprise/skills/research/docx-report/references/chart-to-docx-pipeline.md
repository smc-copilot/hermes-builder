# 图表嵌入Word文档流水线（matplotlib → python-docx）

## 适用场景

当分析报告需要嵌入数据可视化图表（柱状图、饼图、趋势图、雷达图等）时，采用"先独立生成图表PNG，再嵌入Word文档"的两阶段流水线。

## 流水线架构

```
阶段1: 图表生成脚本（matplotlib）
  ↓ 输出PNG到 artifacts/charts/
阶段2: Word报告生成脚本（python-docx）
  ↓ 用 doc.add_picture() 嵌入
最终: .docx文件（含嵌入式图表）
```

## 阶段1：图表生成脚本模板

```python
#!/usr/bin/env python3
"""图表生成脚本 — 独立运行，输出PNG到artifacts/"""
import matplotlib
matplotlib.use('Agg')  # 无头模式，必须
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import numpy as np
import os

output_dir = '/path/to/artifacts/charts'
os.makedirs(output_dir, exist_ok=True)

# ===== 中文字体 setup（Linux必须）=====
font_path = os.path.expanduser('~/.fonts/SimHei.ttf')
if os.path.exists(font_path):
    fm.fontManager.addfont(font_path)
    plt.rcParams['font.sans-serif'] = ['SimHei']
else:
    plt.rcParams['font.sans-serif'] = ['DejaVu Sans']  # fallback
plt.rcParams['axes.unicode_minus'] = False

# ===== 专业配色方案（推荐深蓝系）=====
COLORS = {
    'primary': '#1E2761',   # 深蓝
    'secondary': '#3A7CA5', # 中蓝
    'accent': '#FF6B35',    # 橙红（突出/预警）
    'green': '#2A9D8F',     # 翠绿（正向）
    'muted': '#7A9D96',     # 灰绿（低权重）
    'gold': '#F4A261',      # 金色（中间态）
}

# ===== 图表生成函数示例 =====
def chart_example():
    fig, ax = plt.subplots(figsize=(10, 6))
    # ...图表绘制逻辑...
    plt.tight_layout()
    plt.savefig(f'{output_dir}/chart_01_example.png', dpi=200, bbox_inches='tight')
    plt.close()

# 执行所有图表
chart_example()
```

## 阶段2：Word文档中嵌入图表

```python
from docx import Document
from docx.shared import Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
CHARTS_DIR = '/path/to/artifacts/charts'

def add_chart(filename, width=Inches(5.3), caption=''):
    """嵌入图表到Word文档，可选编号和标题"""
    path = os.path.join(CHARTS_DIR, filename)
    if not os.path.exists(path):
        print(f'[WARN] Chart not found: {filename}')
        return
    if caption:
        cp = doc.add_paragraph()
        cp.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = cp.add_run(caption)
        r.bold = True
        r.font.size = Pt(9)
    doc.add_picture(path, width=width)
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
    doc.add_paragraph()  # 图表后间距

# 使用
add_chart('chart_01_example.png', caption='图1-1：示例图表标题')
```

## 常用图表类型速查

| 图表类型 | matplotlib函数 | 适用场景 |
|---------|---------------|---------|
| 柱状图（bar） | `ax.bar()` | 多期/多维对比 |
| 堆叠柱状图 | `ax.bar(bottom=...)` | 结构演变 |
| 折线图（line） | `ax.plot()` | 趋势变化 |
| 饼图（pie） | `ax.pie()` | 占比分布 |
| 双轴图（twinx） | `ax.twinx()` | 两类量纲叠加（如营收+增速） |
| 雷达图（polar） | `subplot_kw=dict(polar=True)` | 多维对标 |
| 填色图（fill_between） | `ax.fill_between()` | 区间/范围标注 |

## 中文字体安装流程

```bash
# 方案1：下载SimHei.ttf（已验证可行）
python3 -c "
import urllib.request, os
font_dir = os.path.expanduser('~/.fonts')
os.makedirs(font_dir, exist_ok=True)
url = 'https://raw.githubusercontent.com/StellarCN/scp_zh/master/fonts/SimHei.ttf'
urllib.request.urlretrieve(url, os.path.join(font_dir, 'SimHei.ttf'))
print('SimHei.ttf downloaded')
"

# 清除matplotlib缓存
rm -rf ~/.cache/matplotlib

# 验证
python3 -c "
import matplotlib.font_manager as fm
fm.fontManager.addfont(os.path.expanduser('~/.fonts/SimHei.ttf'))
print('Font loaded successfully')
"
```

## 常见坑

1. **matplotlib使用TkAgg后端**：在无GUI环境中必须设置 `matplotlib.use('Agg')`，否则报错
2. **中文字体找不到**：pip安装的matplotlib不包含中文字体，必须手动下载并清除缓存
3. **图表分辨率不够**：用 `dpi=200` 确保嵌入Word后清晰
4. **图表太大撑破页面**：`width=Inches(5.3)` 是A4纸安全宽度（含页边距）
5. **颜色表达不准确**：用深蓝色系（#1E2761）作为主色调，红色仅用于风险/预警标注
