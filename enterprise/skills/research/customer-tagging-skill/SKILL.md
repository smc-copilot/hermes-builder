---
name: customer-tagging-skill
description: >
  画像报告打标签技能——当用户要求从客户画像、原厂画像或其他报告文档中提取"标签"时，
  以统一的打标签方式和命名规则，按主体名称形成标签文档，并给出标签生成的质量评分。
  从画像报告中穷举式提取标签，按 MODE_CUSTOMER（D0-D5）或 MODE_MANUFACTURER（M0-M6）
  框架组织、评分与输出，维护全库唯一统一标签库（客户标签库.json，schema 规则层 +
  objects 数据层，增量 upsert）。v4.0 起新增：细颗粒产品/服务标签（D1.6）与
  产品→芯片需求倒推（D2.6，高置信倒推生成带置信度标签）。当用户要求"给客户/原厂打标签"
  "提取标签""建立标签库""更新标签字典"、或提供画像/报告文档要求提取标签时触发。
version: 4.0
tags: [research, customer-profile, tagging, tag-library, semiconductor-distribution, schema-evolution]
category: research
---

# customer-tagging-skill v4.0（画像报告打标签技能）

> 适用：电子元器件 / 模组 / PCBA / 解决方案，B2B 授权分销、独立分销。
> 版本历史：v2.0 经 TRIAD 双 Agent 审查重构（见 `references/v1-review-findings.md`）；v3.0 依据用户设计校正与评估修复定稿（见 `references/v3-design-fixes.md`）；v4.0 新增 D1.6 产品与服务体系（细颗粒）与 D2.6 产品→芯片需求倒推（高置信带置信度标签），增强撮合机会发现（2026-08-20 用户需求驱动）；上下文受限时可使用精简版 `references/customer-tagging-skill-v2.0-compact.md`（基础能力与细节保留，v4.0 增量见本文 D1.6/D2.6 两节）。首次批量打标签流程见 `references/batch-tagging-playbook.md`；**schema 版本升级后对存量对象回填**（v3.0→v4.0 实测：tag_id 连续性/完整性重算/source_report_id 复用/红线对象不产倒推）见 `references/v4-backfill-playbook.md`。

## 一、角色与纪律

你是 **B2B 客户数据策略专家与标签体系架构师**：从客户/原厂画像报告提取标签，形成可被撮合流程直接消费的标签体系。

三条信念：
1. **穷举检查、精选输出**——内部核对全部分类，只输出有证据标签；
2. **标签是撮合输入**——供产品线匹配 / 客户群分析 / 线索分配使用；
3. **不虚构、不硬凑**——没写 → 标缺口或请求补充；倒推必须有产品实证，禁止凭空倒推。

## 二、输入与输出

**输入**：
- 必选：画像报告（MD / 文本 / JSON）。区分**客户画像**与**原厂画像**；
- 可选：交易数据（对接 `sales-transaction-diagnostics`）、CRM 导出。

**输出**：
1. 每对象一份 MD 标签报告（一次性产物，结构见「十二」）；
2. **全库唯一统一标签库** `客户标签库.json`（固定名不带日期；schema 规则层 + objects[] 数据层，增量 upsert，跨对象查询直接读本库，**无独立索引表**）。

## 三、模式判定（强制第一步）

| 判定依据 | 模式 | 框架 |
|:---|:---|:---|
| 报告主体是**客户**（买/可能买我们东西的企业） | MODE_CUSTOMER | D0-D5（第四节） |
| 报告主体是**原厂/品牌商**（供应方，含已授权品牌） | MODE_MANUFACTURER | M0-M6（第五节） |

不得互套框架；混合输入逐份判定。

## 四、MODE_CUSTOMER 框架（D0-D5）

### D0 撮合门控层（GATE 优先）

| 二级分类 | 说明/典型标签 | 行为 |
|:---|:---|:---:|
| D0.1 业务类型 | 制造 / 贸易 / 方案商DH / EMS代工 / 平台 / 纯软件 | GATE |
| D0.2 合作状态 | 已合作(在供品类) / 待开发；未列在供品类标【待盘点】 | GATE(策略切换) |
| D0.3 风险等级 | 低 / 中 / 高 / 黑名单（引用画像风控节，不重复计算） | GATE(可排除) |
| D0.4 主控/外围 | 主控(SoC/CIS/主控MCU)是否原厂直采锁定；外围配套空间 | GATE(品类级) |

### D1 静态属性

- **D1.1 企业基础**：规模 / 营业额 / 上市 / 所有制 / 地域 / 成立年限 / 工商状态
- **D1.2 行业与供应链角色**：下游应用领域 / 供应链角色代码 / 亿渡编码（产品服务明细归 D1.6）
- **D1.3 联系人**：部门 / 职位职级 / 决策链 / 干系人
- **D1.4 资质认证**：ISO / 行业准入 / 特殊资质
- **D1.5 合作历史**：首次合作时间 / 年限 / 年度框架
- **D1.6 产品与服务体系（v4.0 新增，撮合机会发现的基础）**：
  - **产品线清单**（ARRAY，P1）：**逐产品一条记录**，字段 = 产品/服务名 + 品类归属 + 是否自研 + 技术参数摘要 + 目标市场/下游 + 产品状态（规划/研发/试产/量产/停产）——细颗粒枚举客户对外提供的**全部**产品与服务，不只芯片相关产品；
  - **服务模式**（ENUM，P1）：自有品牌 / OEM代工 / ODM设计 / 方案设计DH / EMS代工 / 贸易分销 / 平台 / 软件开发 / 其他（多选）；
  - **核心产品技术特征**（STRING，P2）：如"40层PCB/HDI全联通""动态人脸识别""5G RedCap网关"；
  - **产品-服务全景覆盖判定**（BOOLEAN，P2）：对照画像产品线概览表/官网产品中心/经营范围，确认是否已穷举全部对外产品与服务（是=COVERED；否=列出缺漏清单）。

### D2 技术需求（核心）

- **D2.1 采购品类偏好**：取值对齐授权产品线 c 表词，原文词记 `dict_alias`，词表外 OTHER（**限画像/交易数据明示的采购**；推断类归 D2.6）
- **D2.2 品牌与货源偏好**：品牌对齐 a 表标准名，非授权标"渠道待确认"；国产替代倾向；是否接受翻新料
- **D2.3 技术参数规格**：封装 / 工作电压 / 温度等级 / 精度 / 主频速率 / 认证要求（受控词表 + OTHER）
- **D2.4 物料生命周期敏感度**：EOL / PCN 关注度 / 替代料需求
- **D2.5 应用与项目**：项目阶段 / 年用量 EAU / 量产进度 / 接口需求
- **D2.6 产品→芯片需求倒推（v4.0 新增，撮合机会发现的引擎）**：
  - **前置条件**：仅当 D1.6 产品线清单已有 **COVERED 实证产品** 时才执行倒推；产品未证实 → 不产倒推标签（标 UNCOVERED/缺口）；
  - **倒推方法**：对每个实证产品，查**产品→芯片强映射参考表（附录 A）**确定映射芯片品类（c 表标准词）；一个产品可映射多品类，但只保留 **STRONG 强映射** 结果；
  - **标签**：**芯片需求倒推清单**（ARRAY，P0）= 每条含【来源产品、映射芯片品类（c 表词）、mapping_strength、inference_basis（产品→映射链路说明）、推荐品牌（a 表）】；
  - **映射强度分档**：STRONG（产品→品类几乎必然，如串口服务器→RS485收发器/PMU/MCU）、MEDIUM（大概率但视设计，如检测仪器→DDR）、WEAK（可能但不确定，如绝缘材料→安防SoC）——**STRONG 才产标签**；MEDIUM/WEAK 进候选池/未覆盖清单；
  - **置信度规则**：倒推标签 `coverage_status = COVERED_WITH_INFERENCE`，confidence 上限 **0.7**（低于 COVERED 实证、高于 HEURISTICS 纯猜测，因为基于产品实证+工程常识映射）；`mapping_strength`、`inference_basis` 字段必填；
  - **转正路径**：倒推品类经 FAE 确认/样品验证/客户确认后，可升级为 D2.1 COVERED 实证品类（confidence 重算）。

### D3 动态行为（仅画像/内部数据可承载子集）

- **D3.1 交易合作动态**：询价频率 / 成交率 / 采购模式 / BOM配单 / 退换货——原始观测，RFM 衍生归 D4.1
- **D3.2 营销互动**：展会 / 研讨会 / 样品申请 / 技术交流
- **D3X 外部扩展轨**：线上行为 / 社媒 / 邮件，仅 CRM 接入时有数据；**不参与完整性评分**；无采集渠道标"本企业不适用"，不请求补充

### D4 商务价值

- **D4.1 RFM 分层**：仅当有交易数据或画像明确给出（衍生层）
- **D4.2 财务与信用**：客单价 / 利润 / 账期 / 信用等级 / 付款记录（引用画像风控节）
- **D4.3 商业潜力**：合作潜力 / 战略价值 / 价格敏感度 / 大单潜力——主观预测性，稳定性分下调

### D5 生命周期与预测

- **D5.1 生命周期阶段**：潜客 / 新客 / 成长 / 成熟 / 衰退 / 休眠 / 流失
- **D5.2 预测预警**：流失风险 / 增购倾向 / 交叉销售（绑定 RFM）
- **D5.3 需求类型预测**：项目型 / 现货型 / 研发样品型

## 五、MODE_MANUFACTURER 框架（M0-M6）

**M0 撮合门控层（与 D0 对称，GATE 优先）**

| 二级分类 | 说明 | 行为 |
|:---|:---|:---:|
| M0.1 授权状态 | 已授权 / 未授权 / 独家 / 竞品重合 | GATE(策略切换) |
| M0.2 合规与制裁 | 实体清单 / 出口管制 | GATE(可排除) |
| M0.3 与我司产品线重叠度 | — | GATE(品类级) |

- **M1 企业基本面**：M1.1 工商与上市；M1.2 规模与财务概况
- **M2 技术与产品线**：M2.1 技术路线与制程（如 Floating Gate vs SONOS）；M2.2 IP 来源与专利（自研/授权）；M2.3 产品线广度深度（品类覆盖/系列完整度/空白品类；**v4.0 增强：输出产品线明细清单（逐系列/逐型号族），与客户 D1.6 产品清单做品类对照，定位可切入的空白品类**）；M2.4 认证体系（AEC-Q100/工规/车规）
- **M3 市场与竞争**：M3.1 市场定位与份额；M3.2 竞争格局（主要对手）；M3.3 国产替代属性（P0）；M3.4 目标客户群
- **M4 供应链与产能**：M4.1 经营模式（Fabless/IDM/Foundry）；M4.2 代工与封测伙伴；M4.3 产能与供货稳定性
- **M5 商务与风险**：M5.1 财务健康度（P0）；M5.2 上市与融资；M5.3 地缘与合规风险
- **M6 代理合作（撮合核心）**：M6.1 授权代理体系；M6.2 与我司产品线重叠度（a 表对照，P0）；M6.3 合作深化机会（套片/交叉销售/新品导入窗口）

**原厂 P0 归属**：M3.3 国产替代 = WEIGHT；M2.3 产品线广度 = WEIGHT；M4.3 供货稳定性 = WEIGHT；M5.1 财务健康度 = GATE(可排除)；M6.2 重叠度 = GATE(品类级，同 M0.3)。

## 六、重要性（P0/P1/P2）与匹配行为（GATE/WEIGHT）

- **GATE 硬筛/策略切换**（仅少数）：业务类型、风险等级、主控锁定（品类级）、原厂授权/合规/重叠度。不满足即排除或切策略；排除注明粒度（客户级/品类级）。休眠客户/RFM 低**不是** GATE（应唤醒/只降分）。
- **GATE×confidence**：GATE 硬筛独立于 confidence 消费门槛——GATE 标签无论 confidence 高低都执行硬筛；confidence<0.6 的 GATE 标签不参与自动打分，强制 PENDING_CONFIRM，人工复核排除/放行后生效。
- **WEIGHT 加权打分**：其余全部标签，满足越多排名越高。
- **P0 核心**：供应链角色、核心采购品类、**芯片需求倒推（STRONG，v4.0）**、下游应用、生命周期阶段、RFM 分层（WEIGHT）。
- **P1 重要**：**产品线清单/服务模式（D1.6，v4.0）**、品牌偏好、封装形式、温度等级、当前项目阶段、价格敏感度、流失风险。
- **P2 辅助**：成立年限、装机量、营销互动频率、核心产品技术特征。

## 七、层级与命名（≤4 层）

第1级 一级维度（D0-D5 / M0-M6）→ 第2级 二级分类 → 第3级 标签名称 → 第4级 标签取值。

- 第3级标签名**同一对象内全局唯一**（跨维度不得重名）。
- 第4级取值：**受控词表 + OTHER 兜底**，不做绝对穷尽；同标签内取值语义互斥（封装 BGA/QFN 与阻容 0402/0603 不混入同一标签）；"穷尽" = 相对授权产品线词表穷尽。
- 品类/品牌取值优先对齐 `authorized-product-line-reference`；**D2.6 倒推品类同样必须用 c 表标准词**。

## 八、单标签 Schema 与统一标签库（必须可机器 parse）

### 8.1 单标签 Schema

```json
{
  "tag_id": "D2-001",
  "dimension_level1": "D2",
  "dimension_name_cn": "技术需求",
  "category_level2": "采购品类偏好",
  "tag_name_cn": "核心采购品类",
  "tag_type": "ENUM",
  "tag_value_options": ["存储(NOR Flash)", "PMU", "功率器件", "OTHER"],
  "tag_value_actual": "存储(NOR Flash), MCU",
  "match_behavior": "WEIGHT",
  "priority": "P0",
  "main_control": "外围",
  "quality_score": 82,
  "confidence_score": 0.75,
  "coverage_status": "COVERED",
  "audit_status": "CONFIRMED",
  "data_source": "画像第X章+原文片段",
  "data_source_type": "PROFILE",
  "as_of_date": "2026-08-03",
  "source_report_id": "20260803_xxx_客户画像报告.md",
  "dict_alias": ["原文用词"],
  "description_cn": "含义与业务用途"
}
```

**D2.6 倒推标签 Schema 示例（v4.0 新增字段）**：

```json
{
  "tag_id": "D2-014",
  "dimension_level1": "D2",
  "dimension_name_cn": "技术需求",
  "category_level2": "产品→芯片需求倒推",
  "tag_name_cn": "芯片需求倒推清单",
  "tag_type": "ARRAY",
  "tag_value_actual": "[{\"source_product\":\"串口服务器/网关\",\"chip_category\":\"RS485/CAN总线\",\"mapping_strength\":\"STRONG\",\"inference_basis\":\"串口服务器必备RS-485收发器（画像产品线实证）\"},{\"source_product\":\"串口服务器/网关\",\"chip_category\":\"PMU\",\"mapping_strength\":\"STRONG\",\"inference_basis\":\"板卡多路供电标配\"}]",
  "match_behavior": "WEIGHT",
  "priority": "P0",
  "main_control": "外围",
  "quality_score": 78,
  "confidence_score": 0.7,
  "coverage_status": "COVERED_WITH_INFERENCE",
  "audit_status": "CONFIRMED",
  "mapping_strength": "STRONG",
  "inference_basis": "串口服务器→RS-485收发器/PMU/MCU 强映射（附录A）",
  "data_source": "画像第2章产品线概览（实证）+ 附录A强映射表",
  "data_source_type": "INFERENCE",
  "as_of_date": "2026-08-03",
  "source_report_id": "20260803_xxx_客户画像报告.md",
  "dict_alias": [],
  "description_cn": "由产品实证倒推的芯片需求，供撮合 L1 候选品类扩展"
}
```

**字段约束**：
- `tag_id` = 维度码-序号；
- `tag_type` ∈ ENUM / NUMERIC / STRING / BOOLEAN / DATE / ARRAY（NUMERIC 带 unit/range、DATE 带 format、ARRAY 说明元素语义）；
- `tag_value_options` 仅 ENUM；
- `match_behavior` 必填；
- `main_control` 品类类标签必填（主控 / 外围 / 不适用）；
- `coverage_status` ∈ COVERED / COVERED_WITH_HEURISTICS / **COVERED_WITH_INFERENCE（v4.0，仅 D2.6 倒推标签，上限 0.7）**（UNCOVERED 不出 schema，只进未覆盖清单）；
- `audit_status` ∈ PENDING_CONFIRM / CONFIRMED / REJECTED；
- `as_of_date`、`source_report_id` 必填；
- D2.6 倒推标签**必填** `mapping_strength`（STRONG/MEDIUM/WEAK）与 `inference_basis`；`data_source_type = INFERENCE`。

### 8.2 统一标签库顶层结构

```json
{
  "library_name": "客户标签库",
  "version": "4.0",
  "updated": "2026-08-20",
  "schema": {
    "dimensions": ["D0 撮合门控", "D1 静态属性(含D1.6产品与服务体系)", "D2 技术需求(含D2.6产品→芯片倒推)", "D3 动态行为", "D4 商务价值", "D5 生命周期"],
    "tag_dictionary": [],
    "changelog": [
      {"date": "2026-08-20", "change": "新增标签：xxx", "trigger": "对象 BLUE-2026", "reason": "多对象通用且撮合价值高"}
    ]
  },
  "objects": [
    {
      "object_id": "BLUE-2026",
      "object_name": "...",
      "mode": "MODE_CUSTOMER",
      "as_of_date": "...",
      "report_date": "...",
      "skill_version": "4.0",
      "completeness_score": 87,
      "tags": []
    }
  ]
}
```

- `schema` 是**新对象打标签的规则来源**（Step 1 先读，不每次从零发明）；
- `version` 自持 vX.Y（X=结构变动、Y=数据增量），变更记 changelog；**v3.0→v4.0 属于结构变动（新增 D1.6/D2.6 分类+coverage_status 新枚举），标签库版本 X 应同步升级**；
- `objects[]` 按 object_id 定位 upsert。

## 九、质量与置信度评分

**quality_score（0-100，5 锚点）= Accuracy×0.4 + Coverage×0.3 + Stability×0.3**

| 维度 | 权重 | 锚点 |
|:---|:---:|:---|
| Accuracy | 0.4 | 原文原话=95；同义表述=80；**产品实证+STRONG 强映射倒推=78~80（v4.0）**；跨字段推断=65；**产品实证+MEDIUM 中映射倒推=60~65（v4.0，不产标签仅进候选池）**；常识启发式=45；无依据=0（禁 COVERED） |
| Coverage | 0.3 | 明确=90；微弱线索=60；无信息=20 |
| Stability | 0.3 | 事实性=90；主观预测性=60；**倒推标签=70（产品实证锚定但品类为推断）** |

**confidence_score（0-1）= quality/100 × time_decay**：
- 静态标签（D0 工商 / D1 / D2 技术类）= 1.0；动态（D3 / D4.1 / D5）按 as_of_date 每 90 天 ×0.9，下限 0.4。
- COVERED_WITH_HEURISTICS 上限 0.6；**COVERED_WITH_INFERENCE 上限 0.7（v4.0，恒满足 conf ≤ quality/100）**；
- **自动撮合只消费 ≥0.6**；<0.6 进人工审核（PENDING_CONFIRM）。**注意：0.6~0.7 的倒推标签可进入自动撮合（机会发现），但命中后必须经 FAE 验证转正才计入高优先级**。

## 十、完整性评分（双层 + 加权）

**画像可承载覆盖度（主评分）**：
- 客户模式 **24 个二级分类**（v4.0 新增 D1.6、D2.6），权重 D0/D2=1.5、D1/D4=1.0、D3/D5=0.5，Σ = 24 + 1.0(D1.6) + 1.5(D2.6) = **26.5**；完整度 = Σ(覆盖二级分类×权重)/26.5×100。
- 原厂模式 22 个二级分类（M0 3 个权重 1.5），M0/M2/M3/M6=1.5、其余 1.0，Σ=29；完整度 = Σ(覆盖二级分类×权重)/29×100（v4.0 原厂仅增强 M2.3 明细，不新增分类）。

| 完整度 | 处置 |
|:---|:---|
| ≥85 | 交付 |
| 60-85 | 部分完整 → 列可补清单降级交付 |
| <60 | 暂停请求补充 |

**外部数据补充需求（副清单，不扣分）**：CRM / 交易 / 社媒等画像承载不了的数据单列"数据接入建议"（如 D4.1 接交易流水、D3X 接 CRM），不参与评分、不阻塞交付。

## 十一、撮合应用

- **消费方**：产品线机会匹配（L0 粗筛 → L1 品类对照 → L2 精读，读 D2.1/D2.2 **+ D2.6 倒推品类**）；客户群分析（P0 + main_control 喂机会卡）；线索分配（GATE 硬筛 + P0-WEIGHT 打分，≥0.6 才自动分配）。
- **v4.0 倒推品类消费规则（机会发现引擎）**：
  - D2.6 STRONG 倒推品类进入 L1 品类对照，作为**候选扩展品类**（区别于 D2.1 实证品类）；L1 命中后标 `INFERENCE` 证据标签；
  - 倒推品类若命中我司授权品牌 → 生成**新业务机会建议**（产品 X → 可推品牌 Y 的品类 Z，作为线索分配候选）；
  - 倒推品类命中后默认**不立即计高优先级分**：需 FAE 验证（规格书比对/样品/客户确认）后转正为 D2.1 实证品类，才按 P0-WEIGHT×3 全额计分；
  - 撮合报告需区分「实证品类命中」与「倒推品类命中」两栏，避免销售误把推断当既定需求。
- **打分**：撮合分 = Σ(P0-WEIGHT 命中×3) + Σ(P1×1.5) + Σ(P2×0.5) − Σ(P1/P2 反向冲突×1)；GATE 全过才生效。默认阈值：≥5.0 高优先(立即跟进)、3.0-4.9 中优先(入池)、<3.0 低优先(暂缓)，可按业务调整；例：6.0 → 高优先。
- **词表对齐**：① D2.1 品类用 c 表标准词（如"功率器件（MOSFET/IGBT/IPM/SiC/GaN）"）；② D2.2 品牌用 a 表标准名，非授权标"渠道待确认"（不默认排除）；③ 不一致时 `tag_value_actual` 用标准词、`dict_alias` 记原文词；④ 词表外新品类 → OTHER + 数据资产更新建议（不擅改）；**⑤ D2.6 倒推品类同样对齐 c 表词，词表外建议数据资产更新后回流倒推**。
- **frontmatter 关系**：L0 等级分直接引用画像原文不重算；D2.1 回写 L1、D1.2 回写 L2；**D1.6 产品清单/服务模式回写 L2 场景索引；D2.6 倒推品类回写 L1 候选品类（标注 INFERENCE）**；JSON 权威细粒度、frontmatter 粗筛索引。

## 十二、输出报告结构（每对象 MD）

```text
# 客户标签提取报告——[名称]
一、概览（维度覆盖/完整度/标签总数 P0-GATE:P0-WEIGHT:P1:P2/门控结论）
二、按维度标签列表（仅 COVERED/HEURISTICS/INFERENCE 出完整字段；UNCOVERED 只列分类名；
     D1.6 产品线清单逐产品列出；D2.6 倒推标签列出【来源产品→倒推品类(mapping_strength/置信)】）
三、重要性分析（GATE/WEIGHT、P0/P1/P2 清单）
四、质量汇总（平均 confidence/quality、最高最低、<0.6 清单）
五、完整性评估（评分+覆盖/未覆盖+判定+数据接入建议）
六、请求用户介入（仅"有渠道但未写"项；无渠道标"不适用"）
七、人工审核项（PENDING_CONFIRM）
八、撮合建议（GATE 结论+切入点主控/外围+实证品类对齐词表+【倒推品类机会清单（待 FAE 验证）】）
九、标签库演进建议（新维度候选+建议动作+版本变更 vX.Y→vX'.Y'）
```

## 十三、落地规范

| 产物 | 命名 | 目录 |
|:---|:---|:---|
| 客户标签报告 | `YYYYMMDD_公司简称_客户标签报告.md` | `/data/hermes/workspace/exports/` |
| 原厂标签报告 | `YYYYMMDD_原厂简称_原厂标签报告.md` | `/data/hermes/workspace/exports/` |
| 统一标签库（全库唯一） | `客户标签库.json`（固定名不带日期） | `/data/hermes/obsidian-vault/客户标签/` |
| 归档（可选） | 同名 .md 副本 | obsidian-vault/客户画像/ 或 60-Reports/ |

**统一标签库维护**：
- **单一权威**：无独立索引表、无按对象独立 JSON，临时 JSON 仅中间产物；
- **双重角色**：schema 规则层 + objects[] 数据层；
- **upsert 语义**：已有 → 整体替换 tags[] 刷新日期；新 → 追加；失效 → `archived: true` 不删除；
- **版本 vX.Y**（结构变动升 X、数据增量升 Y）+ changelog；**v3.0→v4.0 结构变动：新增 D1.6/D2.6 分类、coverage_status 新枚举 COVERED_WITH_INFERENCE、schema.dimensions 文案更新，标签库 version 升 X**；
- **触发时机**：每次打标签任务结束（Step 10）必须更新；
- **并发安全**：upsert 前重读最新文件 + updated 冲突检测，冲突合并重试；并行任务写入串行化。

路径为默认值，支持配置/环境变量覆盖。

## 十四、执行流程（含退出条件）

```text
Step 0  模式判定（CUSTOMER/MANUFACTURER），接收输入
Step 1  读统一标签库 schema（不存在则初始化 v1.0）
Step 2  通读报告，识别特征语句/字段（重点：第2章产品线概览/官网产品中心/经营范围 → D1.6 素材；
        第9章芯片需求推断/产品-芯片匹配表 → D2.6 参考）
Step 3  穷举核对 D0-D5（或 M0-M6）全部分类（不遗漏，含 D1.6/D2.6）
Step 4  提取归位（match_behavior/main_control/priority）
Step 5  词表对齐（品类/品牌规范化，dict_alias 记原文词；D2.6 品类用 c 表词）
Step 6  【D1.6→D2.6 顺序执行】先完成产品线清单（D1.6），再对每个 COVERED 实证产品
        查附录 A 映射表执行倒推（D2.6）；STRONG 才产标签，MEDIUM/WEAK 进候选池
Step 7  质量评分（5 锚点，含 v4.0 倒推锚点）→ confidence（含时效衰减/INFERENCE 上限 0.7）
Step 8  完整性评分（双层+加权，客户模式 Σ=26.5）
Step 9  生成 MD 报告 + 对象 JSON 数据块
Step 10 ≥85 交付；60-85 列清单降级交付；<60 暂停请求补充
Step 11 落地：MD→exports；upsert 入库；Schema 演进（候选→判断特例/可推广→新增/调整/不动→升版本+changelog）；回写 frontmatter（D2.6 标注 INFERENCE）；数据资产建议
```

**退出条件**：无更多补充 → 降级交付，UNCOVERED 标"信息不可得"；补充 ≤2 轮，超限降级标"待数据补齐后重跑"；无采集渠道 → "不适用"不请求。

**批量（多对象）执行要点**（20 对象实战沉淀 2026-08-20，完整流程见 `references/batch-tagging-playbook.md`）：
- **中间产物**：每对象 JSON 数据块先写 `exports/tag_objects/{OBJECT_ID}.json`（合法中间产物），全部完成后**一次性脚本合并入库**——勿逐对象手改库；
- **文件名**：`YYYYMMDD_公司简称_客户标签报告.md`——公司简称（对齐 obsidian 画像文件名），日期 = **生成日**（非画像 as_of_date），全称会产生超长文件名；
- **合并脚本原子完成**：重读最新库 → 按 object_id upsert → 字典扩展（收集全部 tags 的 tag_name_cn 与 schema.tag_dictionary 对比、缺失追加）→ 版本号（无结构变动仅 Y+1，如 v1.0→v1.1）→ changelog → 写回（ensure_ascii=False）；
- **MD 报告脚本化**：按「十二」九节模板批量生成，维度按 D0-D5 固定顺序分组，避免手写 N 份；
- **收尾终验**：对象数 / 标签总数 / object_id 唯一性 / 字典条数 / changelog 条数；
- **词表一致性**：批量场景品类/品牌词仍须逐一对齐 a/c 表（原文词进 dict_alias），实测 20 对象 515 标签全部对齐、字典零新增说明初始化时按框架穷举一次即可覆盖后续对象；
- **v4.0 批量提示**：D1.6/D2.6 是**每对象必查**分类（产品线概览几乎每份画像都有），勿因"画像没有芯片需求表"跳过 D2.6——产品实证即可倒推。

**空输入兜底**：无画像或模式无法判定 → 不产标签、不改库，输出缺失原因请求补充。

## 十五、硬性约束（红线）

1. **禁止虚构**：画像未出现的信息只能标 UNCOVERED（不出 schema）、COVERED_WITH_HEURISTICS（≤0.6）或 **COVERED_WITH_INFERENCE（≤0.7，仅限基于 D1.6 实证产品的 STRONG 倒推）**。**倒推必须有产品实证**：D1.6 产品线清单无 COVERED 产品 → 不产任何倒推标签；MEDIUM/WEAK 映射一律不产 schema。
2. **层级 ≤ 4 层**；词表 + OTHER 兜底。
3. **穷举检查、精选输出**：单对象 COVERED ≤46（P0+P1 ≤28，P2 ≤18），其中 **D1.6 产品/服务标签 ≤8、D2.6 倒推标签 ≤8**（v4.0 配额，较 v3.0 的 40 扩容 6 条专供产品与倒推），超出进候选池。
4. **评分强制**：所有 COVERED/INFERENCE 必有 quality + confidence；体系必有完整性评分。
5. **撮合纪律**：GATE/WEIGHT 分离；自动撮合只消费 ≥0.6；GATE 排除注明粒度；**倒推品类命中默认按机会候选处理，FAE 验证转正后才全额计分**。
6. **用户介入**：补充请求仅限"有渠道但画像未写"；无渠道标"不适用"；最多 2 轮。
7. **输出完整**：报告（十二）+ JSON 入库（八）缺一不可。
8. **时效与冲突**：as_of_date/source_report_id 必填；冲突裁决见下节；倒推标签随产品线变更（新增/停产）刷新。

## 十六、时效与冲突裁决

裁决优先级：**用户口径 > 最新报告 > 汇总表/底表 > 推断**。"当前状态"标签（D0.2 合作状态/在供品类）以用户口径为准，画像未列在供品类标【待盘点】而非"无实证"。多版本矛盾 → 以 as_of_date 最新为准，冲突标签 confidence 降级 + 强制人工审核。刷新：静态（D0-D2）半年；动态（D3/D4.1/D5）季度；**D2.6 倒推标签跟随 D1.6 产品清单刷新（产品新增/停产立即复核倒推结果）**。

## 十七、调用约定

触发：为新的客户/原厂画像报告打标签、建立/更新标签库、更新标签字典时调用。输入：画像报告 + 可选交易数据/CRM。输出：每对象 MD 报告 + 统一标签库增量 upsert。阻塞：完整度<60 暂停；60-85 无法补充 → 降级交付标"部分完整，已知缺口"。联动：`sales-transaction-diagnostics`（交易数据）、`authorized-product-line-reference`（词表 a/c 表，D2.6 品类对齐）、`product-line-opportunity-matching` / `customer-group-analysis`（下游消费，D2.6 机会发现）、`customer-profiling` / `manufacturer-profiling`（画像生产，D1.6 素材=画像第2章产品线概览、D2.6 素材=画像第9章芯片需求推断表）。自评估：维护 golden set（2-3 个定稿对象）抽样重打比对一致率，发现漂移即修订 schema/锚点；v4.0 增加**倒推一致性检查**（同一产品在不同对象中的倒推结果应一致，漂移即修订附录 A 映射表）。

## 十八、术语表（速查）

| 术语 | 定义 |
|:---|:---|
| GATE / WEIGHT | 硬筛/策略切换 vs 加权打分 |
| 主控 / 外围 | 平台锁定件（原厂直采）vs 分销切入面 |
| COVERED / HEURISTICS / INFERENCE / UNCOVERED | 明确可承载 / 启发式推导(≤0.6) / 产品实证强映射倒推(≤0.7，v4.0) / 未提供 |
| mapping_strength | 倒推映射强度：STRONG 产标签 / MEDIUM / WEAK 进候选池（v4.0） |
| 产品-芯片映射表 | 附录 A：产品线→芯片品类的工程常识映射参考，D2.6 倒推依据（v4.0） |
| inference_basis | 倒推链路说明：来源产品→映射品类→依据（v4.0，倒推标签必填） |
| 待盘点 | 画像未列在供品类占位标记（数据盲区，非状态判定） |
| OTHER 兜底 | 词表外新值 |

## 附录 A：产品→芯片 STRONG 强映射参考表（v4.0）

> 用途：D2.6 倒推依据。**仅当客户画像 D1.6 已实证对应产品时才能引用**；品类词对齐授权产品线 c 表。MEDIUM/WEAK 映射不产标签。此表为起点，随实战持续修订（修订走 Schema 演进流程）。

| 客户产品/服务（D1.6 实证） | STRONG 映射芯片品类（c 表词） | 典型器件举例 | 备注 |
|:---|:---|:---|:---|
| 串口服务器 / 网关 / DTU | RS485/CAN总线、PMU、存储(NOR Flash)、MCU、TVS/保护器件、蜂窝模组 | RS-485收发器、LDO/DC-DC | 主控 SoC 通常原厂直采（外围切入） |
| 智能投影 / LED显示设备 | 存储(DDR/LPDDR)、存储(NOR Flash)、PMU、LED驱动/背光驱动、接口芯片、WiFi/BT模组、MCU | HDMI Switch、光源驱动 | SoC 原厂直采，外围+显示配套 |
| 生物识别 / 门禁考勤设备 | IPC/摄像头SoC、CIS图像传感器、存储(NOR Flash)、PMU、WiFi/BT模组、TVS/保护器件、接口芯片 | 读卡器接口、指纹模组接口 | 主控若已授权分销可主控+外围 |
| 检测仪器 / 测试测量设备 | 模拟芯片(ADC/DAC/运放)、MCU、存储(NOR Flash)、PMU、TVS/保护器件、显示驱动、隔离器件 | 高速ADC、CPLD、光耦 | 国产替代窗口大 |
| 专业广电 / 监视器 / 图传 | PMU、电源管理(BMS)、MOSFET、存储(NOR Flash)、接口芯片(HDMI/PD)、LED驱动、无线SoC | PD协议芯片、电池管理芯片 | 视频 SoC 原厂直采 |
| IPC / 网络摄像机 | IPC/摄像头SoC、CIS图像传感器、存储(DDR/LPDDR)、存储(NAND/eSSD)、PMU、WiFi/BT模组、TVS/保护器件 | 镜头马达驱动、eMMC | 主控平台锁定 |
| 工业物联网 / PLC / 控制器 | MCU、RS485/CAN总线、PMU、存储(NOR Flash)、TVS/保护器件、接口芯片、隔离器件 | 光耦、RS-485收发器 | 工规认证要求 |
| 消费电子（TWS/穿戴/小家电） | 无线SoC、MCU、PMU、存储(NOR Flash)、音频芯片、传感器、LED驱动 | 充电管理、霍尔传感器 | 量大价敏 |
| 医疗器械（监护/康复/检测） | MCU、模拟芯片(AFE/运放)、WiFi/BT模组、PMU、隔离器件、存储(NOR Flash) | 生物电AFE、运放 | 医疗认证要求高 |
| PCB / PCBA 代工服务 | 随BOM：MCU、PMU、存储(NOR Flash)、TVS/保护器件、接口芯片、WiFi/BT模组 | 每板必备料 | 需求随客户 BOM，供应渠道定位 |
| 电源 / 充电器 / 适配器 | 电源管理(AC-DC/DC-DC)、功率器件(MOSFET)、PMU、TVS/保护器件、接口芯片(PD) | PWM控制器、同步整流 | 适配器大单潜力 |
| 汽车电子（后装/车规） | MCU、功率器件、MOSFET、RS485/CAN总线、TVS/保护器件、PMU | CAN收发器、车规DC-DC | 需车规认证（映射降为 MEDIUM 除非画像注明车规） |
| 安防设备（视频类） | IPC/摄像头SoC、CIS图像传感器、存储(NOR Flash/NAND)、PMU、TVS/保护器件 | 镜头驱动 | 仅当画像确认视频类产品 |
