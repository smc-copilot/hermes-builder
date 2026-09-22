# Director-Level Research Report Template 总监级研究报告模板

## When to Use
When the user asks for a "深度分析/全面诊断/评估潜力" and expects a professionally formatted report with strategic insights, NOT just data tables.

## Report Structure Template

### 1. 执行摘要
- 一句话结论（部门当前状态：增长什么阶段？盈利水平？核心问题？）
- 3条核心优势（最好反直觉）
- 3条核心风险（必须量化）
- 关键的财务缺口（如：NET AttrGP $27K vs 团队成本 $470K，缺口$443K）

### 2. 业务全景与规模
- Gross Revenue vs NET Revenue 双重表（按季度）
- 月度走势图描述（U型/V型/L型）
- 关键：解释Q2下滑原因（日本客户流失等）

### 3. 盈利能力深度剖析
- 毛利率分层表（按业务类型/产品线）
- 核心发现1：独立分销vs自采的毛利率差距
- 核心发现2：超低毛利客户的真实盈亏（含隐性成本）
- 核心发现3：成本缺失的估算影响

### 4. 客户结构与集中度风险
- Top 10 客户表（营收+毛利+毛利率）
- 集中度量化：Top 1占比，Top 3占比
- 关键人风险：单一销售对接大客户
- 客户流失专题（如日本客户）

### 5. 团队效能评估
- 销售人效排序表（营收/毛利/单数/单均）
- 关键人风险量化（如某销售贡献82%毛利）
- 无效人力成本估算
- 团队结构合理性诊断

### 6. 隐藏优势识别
- 反直觉信号（如：虽然亏损但新客户拓展加速度显著）
- 技术壁垒（自营平台、数据积累）
- 协同潜力（与集团其他部门的联动机会）

### 7. 结构性风险诊断
- 财务可持续性（毛利率 vs 成本率剪刀差）
- 商业模式本质（分销 vs 方案 vs 平台）
- 业务类型失衡（高营收低毛利占比过大）
- 盈亏平衡路径计算（当前路径/优化路径）

### 8. 总监洞察：战略重构建议
- 短期止血（Q1-Q2可执行的1-3个动作）
- 中期转型（Q3-Q4需启动的战略调整）
- 关键临界点计算（盈亏平衡所需的毛利/营收/成本）

## Key Analysis Dimension Ordering
Always compute in this sequence for consistency:
1. Quarterly P&L (NET + Gross dual view)
2. Business type margin breakdown
3. Customer Pareto + concentration
4. Salesperson efficiency ranking
5. Product category margin analysis
6. Monthly trend (explain U/V shape)
7. Split/deduction impact
8. Hidden signals (growth customers, new customer acceleration)
9. Strategic recomputation (breakeven scenario)

## Word Formatting Conventions for Chinese Reports
- 正文字体：Calibri + 微软雅黑（通过 `style.element.rPr.rFonts.set(qn('w:eastAsia'), '微软雅黑')`）
- 标题用 `doc.add_heading()` 自动使用内置样式
- 表格用 `Light Grid Accent 1` 样式
- 警告文字用红色 RGBColor(255,0,0)
- 非核心补充文字用灰色 RGBColor(128,128,128)
- 表格标题行：加粗 + 居中
- 第一列：加粗（指标名）
- 金额单位统一用美元（$），除非用户指定

## Pitfalls: Director Report Writing
1. **不要只给数据不给判断**——总监报告的价值是"从数据中读出故事"
2. **每个数字都要有"so what"**——不要问"毛利率9%"而是说"毛利率9%意味着每卖$100只赚$9，而运营成本$47万需要卖$522万才能保本"
3. **矛盾信号的裁决**——如：Q4增长121%是好消息，但同时毛利率降到6.8%是坏消息。需要裁决哪个更本质
4. **反直觉信号优先**——如：虽然整体亏损，但新客户获取加速度证明平台有效
5. **行动建议必须可量化**——不要说"降低成本"而说"压缩2-3个技术岗位可节省$8-12万/年"
6. **盈亏平衡计算要给出双路径**——当前路径（维持费率需多少营收）vs 优化路径（调结构后需多少）
