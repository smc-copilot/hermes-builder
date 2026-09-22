# 报告输出统一交付规范（跨 skill 约定）

> 生效日期：2026-09-17。此约定由一次全库审计确立，凡「产出 Word(.docx) 报告」的 skill 都必须遵守。

## 一、约定内容（两要素）

每个带 Word 报告输出的 skill，在报告 `.docx` 生成后，**除该 skill 既有的展示要求外**，还必须同时满足：

1. **点击下载链接**：在结果对话框中用 `MEDIA:/绝对路径/<文件名>.docx` 语法展示 Word 报告的点击下载链接，让用户直接点击下载（Hermes WebUI 的 `MEDIA:` 前缀会渲染为可点击下载的富预览）。
2. **空文件防护**：展示下载链接**之前**，必须先用 `ls -lh` 或 `wc -c` 确认 `.docx` 非空（> 0 字节）。若文件为 0 字节或生成失败，**不得**展示下载链接，须如实报告转换失败原因，杜绝用户点击下载到空文件。

### 标准措辞模板（可直接复用）

```markdown
**展示点击下载链接（强制）**：`.docx` 生成并验证非空后，除上述展示要求外，必须在结果对话框中展示 Word 报告的**点击下载链接**，让用户直接点击下载：`MEDIA:/data/hermes/workspace/exports/<文件名>.docx`。**空文件防护**：展示链接前必须用 `ls -lh` 或 `wc -c` 确认 `.docx` 非空（> 0 字节）；若为 0 字节或生成失败，不得展示下载链接，须如实报告失败原因。
```

## 二、已覆盖 skill 清单（11 个）

| Skill | 插入位置锚点 |
|-------|-------------|
| `docx-report` | Step 4 验证后 → Step 5 |
| `customer-profiling` | 报告输出执行流程第 3/4 步之间 |
| `manufacturer-profiling` | 「输出验证」章节后 |
| `enterprise-risk-analysis` | DOCX 输出第 3 步后（3b） |
| `trade-compliance-analysis` | §12.1 校验段后 |
| `business-data-analysis-methodology` | 双格式输出段后 |
| `sales-transaction-diagnostics` | Phase 7 Word 生成段末尾 |
| `sales-rep-portfolio-analysis` | 输出规范命令行后 |
| `sales-team-portfolio-analysis` | 双格式输出段后 |
| `industry-search` | 交付规范第 3 步后（第 4 步） |
| `b2b-contact-finder` | DOCX 自动转换协议第 4/5 步之间 |

## 三、跳过清单（不产 Word 报告，勿重复加）

- **纯数据资产**：`authorized-product-line-reference`、`industry-chip-dictionary`、`distributor-advantage-brand-dictionary` —— 只提供数据，不产出分析报告。
- **非 Word 输出**：`pptx-deck-generation`（.pptx，已有 `MEDIA:` 交付）、`customer-tagging-skill`（.md + .json）、`product-line-sales-lead-mining`（表格清单，无 docx）、`competitor-news-monitor`（无报告文件交付）。
- **通用能力 skill**（`docx`、`pptx`、`xlsx`、`pdf` 等）：非「报告输出」业务 skill，不适用。

## 四、验证方法（新增 skill 时复用）

修改后全库 grep 标记串确认落盘：

```
search_files(pattern="展示点击下载链接（强制）", path="/data/hermes/skills", output_mode="files_only")
```

期望命中数 = 已覆盖 skill 数（当前 11）。若新增了带报告输出的 skill，应同步补充该 skill 的下载链接要求，并把本清单第二表更新。

## 五、何时需重新审视

- 新建一个产出 `.docx` 报告的 skill → 必须内置此要求。
- 某个 skill 新增了 docx 输出能力 → 补上此要求。
- 用户更改了交付偏好（如改为推企微、改为不同下载语法）→ 回本文件改「标准措辞模板」，再批量同步到 11 个 skill。
