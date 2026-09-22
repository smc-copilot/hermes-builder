# PDF生成参考：Markdown → 专业PDF（含中文支持）

> 用于将原厂画像报告（或客户画像报告）从 Markdown 转换为带专业排版的 A4 PDF。

## 依赖安装

```bash
pip install markdown weasyprint
```

## CJK 字体

PDF渲染需要中文/日文/韩文字体。推荐 Noto Sans CJK SC（简体中文）。

- **下载 URL**：[NotoSansCJKsc-Regular.otf](https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf)（~16MB）
- **备用**：`~/.fonts/NotoSansCJKsc-Regular.otf`（脚本自动下载）

> **已知问题**：
> - jsDelivr CDN（`cdn.jsdelivr.net`）对 `AimeeMao/Fonts` 仓库返回 `Failed to fetch` 错误，不可用
> - Google Fonts API 的 `NotoSansSC[wght].ttf` 下载可能超时
> - **唯一确认可用**：GitHub Raw `raw.githubusercontent.com/notofonts/noto-cjk`

## 转换流程

1. 读取 Markdown 文件
2. 移除 YAML Frontmatter（`---` 包围的元数据块）
3. 移除 Mermaid 代码块（静态 PDF 无法渲染）
4. `markdown.markdown()` 转换为 HTML（启用 `tables`, `fenced_code`, `nl2br`, `sane_lists`）
5. `weasyprint.HTML(string=html).write_pdf()` 生成 PDF

## 已知问题与解决

| 问题 | 现象 | 解决 |
|------|------|------|
| **pandoc/wkhtmltopdf 未安装** | `pandoc not found` | 使用 Python 原生方案（markdown+weasyprint），无需系统级依赖 |
| **中文乱码** | pypdf 提取的文字显示为乱码 | pypdf 不支持 CID-keyed CJK 字体的 CMap 解析，但**视觉渲染正常**——这是 pypdf 文本提取的局限，非 PDF 质量问题 |
| **表格宽度溢出** | 长表格超出页面 | weasyprint 自动处理，无需额外配置 |
| **Mermaid 图无法渲染** | 静态 PDF 中 Mermaid 显示为原始代码 | 转换前 `re.sub(r'```mermaid\n.*?\n```', '', content)` 移除 |

## CSS 样式要点

- `@page size: A4`，边距 `1.8cm / 1.5cm / 2.0cm`
- `@page @bottom-center`：居中页码
- `@page @top-right`：报告标题（首页隐藏）
- `@font-face`：指定 CJK 字体路径
- 表格：`.data-table` 深蓝色表头（`#1a3a5c`）+ 斑马纹（`#f7f9fb` 偶数行）
- 标题层级色阶：h1→`#1a3a5c`（主色），h2→`#1a3a5c`+底线，h3→`#2d5a88`，h4→`#3a6a9e`

## 使用示例

```bash
# 在原厂画像报告生成后，可选执行 PDF 转换
python3 convert_md_to_pdf.py "原厂画像_星宸科技_20260604.md"
# 输出：原厂画像_星宸科技_20260604.pdf
```