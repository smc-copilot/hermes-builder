# 批量打标签执行 Playbook（≥5 对象实战沉淀 2026-08-20）

> 适用范围：一次处理多份客户/原厂画像（实测 20 份客户画像、515 条标签、2 万+ 行输入）。
> 单对象流程见 SKILL.md 第十四节；本文件解决批量场景的工程化问题（侦察→逐份→合并→报告→终验）。
> **注意**：本文完整度数字为 v3.0 口径（Σ=24）；v4.0 引入 D1.6/D2.6 后 Σ=26.5，存量对象重算为 65-85，新增标签的 tag_id/完整性/source_report_id 处理见 `references/v4-backfill-playbook.md`。

## 0. 侦察（先建全局视图，再逐份精读）

- 画像文件通常在 `obsidian-vault/客户画像/`。**MCP workspace 工具可能无权访问该目录**（allowed dirs 不含 obsidian-vault）→ 用 `read_file` / `write_file` / `terminal` 操作该路径。
- 用 Python 脚本**批量抽取全部 frontmatter** 建立概览（一次打印 20 行）：
  - 字段：`company / industry / cooperation_status / profile_grade / tags_l1_supplying / tags_l1_opportunity / tags_l2_scenarios / tags_l2_expansion_path`
  - **陷阱**：`tags_l1_*` 是 YAML 折叠块（`>-` 多行），单行 `key: value` 解析抓不到 → 需按 `^key: >-\n((?:\s+.*\n)+)` 正则提取折叠内容；`tags_l2_scenarios` 是列表块。
  - 目录里可能有索引/名单辅助文件（如 `FRONTMATTER_索引.md`、`待开发客户名单.md`），glob `*画像*.md` 或 `*客户画像*` 过滤出真正的画像。
- 同时检查：`客户标签库.json` 是否存在（不存在 → 先初始化 v1.0：schema 规则层 + tag_dictionary 按框架穷举一次）；`authorized-product-line-reference` 的 a/c 表（每次实时 skill_view 加载，不缓存）。

## 1. 逐份处理（串行，保词表/评分一致性）

- 每份：`read_file` 全文（300-500 行，一次读完或分两段）→ 穷举核对 D0-D5 全部分类 → 生成对象 JSON 数据块到 `exports/tag_objects/{OBJECT_ID}.json`。
- **object_id 命名**：`{英文/拼音简称}-{YYYY}`（如 `BLUE-2026` 蓝之洋、`ZHUOLAN-2026` 卓岚、`99DEG-2026` 九十九度），跨对象唯一；object_name 用工商全称。
- **产出基准**（实测）：单对象 22-27 条标签（红线 ≤40）；每对象必有 quality + confidence + as_of_date + source_report_id；HEURISTICS 推导标 PENDING_CONFIRM 且 confidence ≤0.6。
- 逐份读全文时**顺手记录 frontmatter 的 L1 机会标签**（tags_l1_opportunity），与 D2.1 品类对齐核对。

## 2. 合并入库（一次性脚本，勿逐对象手改库）

先校验全部中间 JSON：
```python
assert obj['mode'] == 'MODE_CUSTOMER'
assert all('tag_id' in t and 'quality_score' in t and 'confidence_score' in t for t in obj['tags'])
```
再合并（对应 Step 10）：
1. **重读最新** `客户标签库.json`（并发安全要求）；
2. 按 object_id **upsert**（已有→整体替换 tags[]；新→追加）；
3. **字典扩展**：收集全部对象 tags 的 `tag_name_cn`，与 `schema.tag_dictionary` 对比，缺失则追加（dimension/category/match_behavior/priority 从标签带出）——实测初始字典 36 条已覆盖 515 条标签全部名称，说明初始化时按框架穷举一次即可；
4. **版本号**：无结构变动只加数据 → Y+1（v1.0→v1.1）；有 schema 结构变动才 X+1；
5. **changelog** 记一条批量事件（date/change/trigger/reason）；
6. 写回（`ensure_ascii=False, indent=2`）。

## 3. MD 报告生成（脚本模板化）

- **文件名**：`YYYYMMDD_公司简称_客户标签报告.md`——日期 = 生成日；简称对齐 obsidian 画像文件简称（勿用工商全称，超长文件名）。
- 用 Python 脚本按「十二」九节结构批量生成：概览 / 按维度标签列表 / 重要性 / 质量汇总 / 完整性 / 请求介入 / 人工审核 / 撮合建议 / 演进建议。
- 维度分组按 D0→D5 固定顺序；每标签行输出 `tag_id | tag_name_cn | value | match_behavior/priority | Q/C | coverage_status`。
- **完整性判定预期**：批量 20 份实测 68-83/100，全部 60-85 区间 → 降级交付（原因主要是 D2.3 技术参数规格、D2.4 生命周期敏感度多数画像未写 → UNCOVERED）；单份 >85 少见，属正常，不必为凑分虚构。

## 4. 收尾

- 终验脚本：对象数 / 标签总数 / object_id 唯一性 / 字典条数 / changelog 条数 / schema dimensions；
- 汇总报告标注：完整度 Top/Bottom、门控结论（GATE 全过 vs 低置信待复核）、词表对齐说明、Schema 演进裁决（本次无新维度 → 仅升 Y）；
- 可选：回写画像 frontmatter（tags 摘要）、归档 MD 副本到 obsidian。

## 5. 质量纪律速查（批量场景易漂移点）

- 同品类在多个对象间取值必须一致（对齐 c 表标准词），如"SPI NorFlash→存储(NOR Flash)"、"WiFi模组→WiFi/BT模组"；
- 品牌名对齐 a 表标准名（Sigmastar/恒烁/贝岭/应能微/士兰微/Nanya），非授权标"渠道待确认"；
- 主控直采锁定（如丽欧 IPC SoC、蓝之洋 MFI/Qi）→ D0.4 标"外围"并 GATE(品类级)；主控已供（中德 SigmaStar）→"主控+外围"；
- 历史交易实证（电商订单/芯智云流水）是最高置信度标签来源，优先引用。
