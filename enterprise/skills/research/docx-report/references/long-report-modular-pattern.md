# 长篇报告模块化拆解模式

## 问题

当生成超过20,000字的投资分析、深度研究报告等内容时，单文件脚本会导致：
- 文件体积过大，`write_file` 接近或超过隐式大小限制
- Lint 检查超时
- 后期修改困难（改一处需重写整个文件）

## 解决方案：内容-构建分离

将报告拆分为"纯数据的内容模块文件"和"一个主构建脚本"。

### 目录结构

```
workspace/scripts/
  content_a.py        # 摘要 + 公司概况 + 行业分析
  content_b.py        # 营收增长 + 利润质量
  content_c.py        # 产能扩张 + 研发壁垒 + 市场空间
  content_d.py        # 管理层 + 负面清单 + 估值 + 结论
  content_e.py        # 报表穿透 + 产业链专题 + 附录
  build_report.py     # 主构建脚本（导入所有content模块并拼接生成docx）
```

### 内容模块文件格式

每个 `content_*.py` 文件遵循统一的数据结构：

```python
# content_a.py
# -*- coding: utf-8 -*-
"""报告内容模块A"""

C = []  # 统一的内容列表，由主脚本导入

def h1(t): C.append(('h1', t))
def h2(t): C.append(('h2', t))
def h3(t): C.append(('h3', t))
def p(t, bold=False): C.append(('p', t, bold))
def tb(headers, rows): C.append(('table', headers, rows))
def pb(): C.append(('pb',))

# ============ 正文 ============
h1('第一章  标题')
h2('1.1 小节')
p('正文段落内容……', bold=False)
tb(['列1', '列2'], [['值1', '值2']])

# 以此类推……
```

关键规则：
- **每个模块仅定义数据**，不 import docx，无文件系统操作
- h1/h2/h3/p/tb/pb 均为辅助函数，简化内容追加
- 元组格式：`('h1', text)`, `('h2', text)`, `('p', text, bold_flag)`, `('table', headers, rows)`, `('pb',)`
- 每个模块文件末尾的 `C` 变量被主脚本导入

### 主构建脚本格式

```python
# build_report.py
import importlib.util, os

BASE = os.path.dirname(os.path.abspath(__file__))

def load_module(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(BASE, name + '.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.C

# 按章节顺序导入
modules = ['content_a', 'content_b', 'content_c', 'content_d']
CONTENT = []
for mod in modules:
    CONTENT.extend(load_module(mod))

# 初始化 Document，设置样式，生成封面和目录……

# 遍历 CONTENT 渲染正文
for item in CONTENT:
    kind = item[0]
    if kind == 'h1': add_heading_styled(item[1], 1)
    elif kind == 'h2': add_heading_styled(item[1], 2)
    elif kind == 'p': add_para(item[1], bold=item[2])
    elif kind == 'table': add_table(item[1], item[2])
    elif kind == 'pb': doc.add_page_break()

# 保存 + 字数验证
doc.save(output_path)
```

### 字数验证代码（含表格）

```python
from docx import Document
doc = Document(path)
total = sum(len(p.text) for p in doc.paragraphs)
for t in doc.tables:
    for row in t.rows:
        for cell in row.cells:
            total += len(cell.text)
print(f'总字符数(含表格): {total}')
```

## 已验证的配置

本次帝科股份报告的实际配置：
- 6个内容模块（a–f），共计约37,000字符
- 287个段落，15张表格
- 每个模块约7,000–8,000字，处于安全大小内
- 生成耗时正常，lint 零报错

## 常见问题

**Q: 模块间需要共享变量（如日期）？**
A: 在主构建脚本中定义，通过全局变量传递给各模块；或将上下文数据写在一个独立的 `context.py` 中由各模块 import。

**Q: 需要修改某个章节？**
A: 只修改对应的 content_*.py 文件，无需改动其他模块或主脚本。

**Q: 字数不够怎么办？**
A: 追加新的内容模块并加入 `modules` 列表即可，无需重构已有代码。
