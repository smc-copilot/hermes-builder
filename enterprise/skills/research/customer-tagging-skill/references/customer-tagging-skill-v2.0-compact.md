# customer-tagging-skill v2.0（压缩版，3,848 字 Word 口径）

> 由完整版 v2.0 压缩而来：能力与细节 100% 保留（框架/评分/撮合纪律/红线），删除历史教训、背景叙述、重复表述。上下文受限时可直接使用本版。

## 一、角色与纪律

B2B 客户数据策略专家与标签体系架构师。从客户/原厂画像报告中系统提取标签，形成可被撮合流程直接消费的标签体系。
三条信念：①穷举检查、精选输出（内部核对全部分类，只输出有证据标签）；②标签是撮合输入（供产品线机会匹配/客户群分析/线索分配使用）；③不虚构、不硬凑（报告没写→标缺口或请求补充，绝不编值）。

## 二、输入与输出

输入：必选 画像报告（MD/文本/JSON），区分**客户画像**与**原厂画像**；可选 交易数据（TSV/CSV，对接 sales-transaction-diagnostics）、CRM 导出。
输出：①每对象一份 MD 标签报告（一次性产物，结构见「十二」）；②**全库唯一统一标签库** `客户标签库.json`（固定名、不带日期；schema 规则层 + objects[] 数据层，按对象增量 upsert，跨对象查询直接读本库，无独立索引表）。

## 三、模式判定（强制第一步）

报告主体是客户（买/可能买我们东西的企业）→ **MODE_CUSTOMER（D0-D5）**；是原厂/品牌商（供应方，含已授权品牌）→ **MODE_MANUFACTURER（M1-M6）**。不得互套框架；混合输入逐份判定。

## 四、MODE_CUSTOMER 框架（D0-D5）

**D0 撮合门控层（GATE 优先）**
| 二级分类 | 说明/典型标签 | 行为 |
|:---|:---|:---:|
| D0.1 业务类型 | 制造/贸易/方案商DH/EMS代工/平台/纯软件 | GATE |
| D0.2 合作状态 | 已合作(在供品类)/待开发；画像未列在供品类标【待盘点】 | GATE(策略切换) |
| D0.3 风险等级 | 低/中/高/黑名单（引用画像风控节，不重复计算） | GATE(可排除) |
| D0.4 主控/外围 | 主控(SoC/CIS/主控MCU)是否原厂直采锁定；外围配套空间 | GATE(品类级) |

**D1 静态属性**：D1.1 企业基础（规模/营业额/上市/所有制/地域/成立年限/工商状态）；D1.2 行业与供应链角色（下游应用领域/产品服务/供应链角色代码/亿渡编码）；D1.3 联系人（部门/职位职级/决策链角色/关键干系人）；D1.4 资质认证（ISO/行业准入/特殊资质）；D1.5 合作历史（首次合作时间/年限/年度框架）。

**D2 技术需求（核心）**：D2.1 采购品类偏好（取值对齐授权产品线 c 表词，原文词记 dict_alias，词表外 OTHER）；D2.2 品牌与货源偏好（品牌对齐 a 表标准名，非授权标"渠道待确认"；国产替代倾向；是否接受翻新料）；D2.3 技术参数规格（封装/工作电压/温度等级/精度/主频速率/认证要求，受控词表+OTHER）；D2.4 物料生命周期敏感度（EOL/PCN 关注度/替代料需求）；D2.5 应用与项目（项目阶段/年用量EAU/量产进度/接口需求）。

**D3 动态行为（仅画像/内部数据可承载子集）**：D3.1 交易合作动态（询价频率/成交率/采购模式/BOM配单/退换货——原始观测，RFM 衍生归 D4.1）；D3.2 营销互动（展会/研讨会/样品申请/技术交流）；D3X 外部扩展轨（线上行为/社媒/邮件，仅 CRM 接入时有数据；**不参与完整性评分**；无采集渠道标"本企业不适用"，不请求补充）。

**D4 商务价值**：D4.1 RFM 分层（仅当有交易数据或画像明确给出；衍生层）；D4.2 财务与信用（客单价/利润/账期/信用等级/付款记录，引用画像风控节）；D4.3 商业潜力（合作潜力/战略价值/价格敏感度/大单潜力——主观预测性，稳定性分下调）。

**D5 生命周期与预测**：D5.1 生命周期阶段（潜客/新客/成长/成熟/衰退/休眠/流失）；D5.2 预测预警（流失风险/增购倾向/交叉销售，绑定 RFM）；D5.3 需求类型预测（项目型/现货型/研发样品型）。

## 五、MODE_MANUFACTURER 框架（M1-M6）

- **M1 企业基本面**：M1.1 工商与上市；M1.2 规模与财务概况
- **M2 技术与产品线**：M2.1 技术路线与制程（如 Floating Gate vs SONOS）；M2.2 IP 来源与专利（自研/授权）；M2.3 产品线广度深度（品类覆盖/系列完整度/空白品类）；M2.4 认证体系（AEC-Q100/工规/车规）
- **M3 市场与竞争**：M3.1 市场定位与份额；M3.2 竞争格局（主要对手）；M3.3 国产替代属性（P0）；M3.4 目标客户群
- **M4 供应链与产能**：M4.1 经营模式（Fabless/IDM/Foundry）；M4.2 代工与封测伙伴；M4.3 产能与供货稳定性
- **M5 商务与风险**：M5.1 财务健康度（P0）；M5.2 上市与融资；M5.3 地缘与合规风险
- **M6 代理合作（撮合核心）**：M6.1 授权代理体系；M6.2 与我司产品线重叠度（a 表对照，P0）；M6.3 合作深化机会（套片/交叉销售/新品导入窗口）
- 原厂 P0 建议：M3.3、M2.3、M6.2、M5.1、M4.3

## 六、重要性（P0/P1/P2）与匹配行为（GATE/WEIGHT）

- **GATE 硬筛/策略切换**（仅少数）：业务类型、风险等级、主控锁定（品类级）。不满足即排除或切策略；排除注明粒度（客户级/品类级）。休眠客户/RFM 低**不是** GATE（应唤醒/只降分）。
- **WEIGHT 加权打分**：其余全部标签，满足越多排名越高。
- P0 核心：供应链角色、核心采购品类、下游应用领域、生命周期阶段、RFM 分层（WEIGHT）。
- P1 重要：品牌偏好、封装形式、温度等级、当前项目阶段、价格敏感度、流失风险。
- P2 辅助：成立年限、装机量、营销互动频率。

## 七、层级与命名（≤4 层）

第1级 一级维度(D0-D5/M1-M6) → 第2级 二级分类 → 第3级 标签名称 → 第4级 标签取值。
- 第3级标签名**同一对象内全局唯一**（跨维度不得重名）。
- 第4级取值：**受控词表+OTHER 兜底**，不做绝对穷尽；同一标签内取值语义互斥（封装 BGA/QFN 不得与阻容 0402/0603 混入同一标签）；"穷尽"=相对授权产品线词表穷尽。
- 品类/品牌取值优先对齐 `authorized-product-line-reference`。

## 八、单标签 Schema 与统一标签库（必须可机器 parse）

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

字段约束：tag_id=维度码-序号；tag_type∈ENUM/NUMERIC/STRING/BOOLEAN/DATE/ARRAY（NUMERIC 带 unit/range、DATE 带 format、ARRAY 说明元素语义）；tag_value_options 仅 ENUM；match_behavior 必填；main_control 品类类标签必填（主控/外围/不适用）；coverage_status∈COVERED/COVERED_WITH_HEURISTICS（UNCOVERED 不出 schema，只进未覆盖清单）；audit_status∈PENDING_CONFIRM/CONFIRMED/REJECTED；as_of_date、source_report_id 必填。

**统一标签库顶层结构**：
```json
{
  "library_name": "客户标签库", "version": "2.1", "updated": "2026-08-20",
  "schema": {"dimensions": ["D0 撮合门控"...], "tag_dictionary": [...],
    "changelog": [{"date", "change", "trigger", "reason"}]},
  "objects": [{"object_id": "BLUE-2026", "object_name": "...", "mode": "MODE_CUSTOMER",
    "as_of_date": "...", "report_date": "...", "skill_version": "2.0",
    "completeness_score": 87, "tags": []}]
}
```
- schema 是**新对象打标签的规则来源**（Step 1 先读，不每次从零发明）；version 自持 vX.Y（X=结构变动、Y=数据增量），变更记 changelog；objects[] 按 object_id 定位 upsert。

## 九、质量与置信度评分

**quality_score（0-100，5 锚点）= Accuracy×0.4 + Coverage×0.3 + Stability×0.3**
- Accuracy：原文原话=95；同义表述=80；跨字段推断=65；常识启发式=45；无依据=0（禁 COVERED）
- Coverage：明确=90；微弱线索=60；无信息=20
- Stability：事实性=90；主观预测性=60

**confidence_score（0-1）= quality/100 × time_decay**：静态标签（D0 工商/D1/D2 技术类）=1.0；动态（D3/D4.1/D5）按 as_of_date 每 90 天 ×0.9，下限 0.4。COVERED_WITH_HEURISTICS 上限 0.6。恒有 confidence ≤ quality/100。**自动撮合只消费 ≥0.6**；<0.6 进人工审核（PENDING_CONFIRM）。

## 十、完整性评分（双层+加权）

**画像可承载覆盖度（主评分）**：客户模式 22 个二级分类，权重 D0/D2=1.5、D1/D4=1.0、D3/D5=0.5，Σ=24；完整度=Σ(已覆盖二级分类×权重)/24×100。原厂模式 19 个二级分类，M2/M3/M6=1.5、其余 1.0。
- ≥85 高完整度→交付；60-85 部分完整→列可补清单+允许降级交付；<60 严重不完整→暂停请求补充。
**外部数据补充需求（副清单，不扣分）**：CRM/交易/社媒等画像承载不了的数据单列"数据接入建议"（如 D4.1 需接交易流水、D3X 需接 CRM），不参与评分、不阻塞交付。

## 十一、撮合应用

- **消费方**：产品线机会匹配（L0 粗筛→L1 品类对照→L2 全文精读，读 D2.1/D2.2）；客户群分析（P0+main_control 喂机会卡）；销售线索分配（GATE 硬筛+P0-WEIGHT 打分，≥0.6 才自动分配）。
- **打分**：撮合分 = Σ(P0-WEIGHT 命中×3) + Σ(P1×1.5) + Σ(P2×0.5) − Σ(P1/P2 反向冲突×1)；GATE 全过才生效。
- **词表对齐**：①D2.1 品类用 c 表标准词（如"功率器件（MOSFET/IGBT/IPM/SiC/GaN）"而非自由写法）；②D2.2 品牌用 a 表标准名，非授权标"渠道待确认"（不默认排除）；③不一致时 tag_value_actual 用标准词、dict_alias 记原文词；④词表外新品类→OTHER+数据资产更新建议（不擅改）。
- **frontmatter 关系**：L0 等级分直接引用画像原文不重复计算；D2.1 回写 L1、D1.2 回写 L2；JSON 为权威细粒度、frontmatter 为粗筛索引。

## 十二、输出报告结构（每对象 MD）

```
# 客户标签提取报告——[名称]
一、概览（维度覆盖/完整度/标签总数 P0-GATE:P0-WEIGHT:P1:P2/门控结论）
二、按维度标签列表（仅 COVERED/HEURISTICS 出完整字段；UNCOVERED 只列分类名）
三、重要性分析（GATE/WEIGHT、P0/P1/P2 清单）
四、质量汇总（平均 confidence/quality、最高最低、<0.6 清单）
五、完整性评估（评分+覆盖/未覆盖+判定+数据接入建议）
六、请求用户介入（仅"有渠道但画像未写"项；无渠道标"不适用"）
七、人工审核项（PENDING_CONFIRM）
八、撮合建议（GATE 结论+切入点主控/外围+可撮合品类对齐词表）
九、标签库演进建议（新维度候选+建议动作+版本变更 vX.Y→vX'.Y'）
```

## 十三、落地规范

| 产物 | 命名 | 目录 |
|:---|:---|:---|
| 客户标签报告 | YYYYMMDD_公司简称_客户标签报告.md | /data/hermes/workspace/exports/ |
| 原厂标签报告 | YYYYMMDD_原厂简称_原厂标签报告.md | /data/hermes/workspace/exports/ |
| 统一标签库（全库唯一） | 客户标签库.json（固定名不带日期） | /data/hermes/obsidian-vault/客户标签/ |
| 归档（可选） | 同名 .md 副本 | obsidian-vault/客户画像/ 或 60-Reports/ |

**统一标签库维护**：单一权威（无独立索引表、无按对象独立 JSON，临时 JSON 仅中间产物）；双重角色（schema 规则层 + objects[] 数据层）；upsert 语义（已有→整体替换 tags[] 刷新日期；新→追加；失效→archived:true 不删除）；版本 vX.Y（结构变动升 X、数据增量升 Y）+ changelog；触发时机=每次打标签任务结束（Step 10）必须更新。

## 十四、执行流程（含退出条件）

```
Step 0  模式判定（CUSTOMER/MANUFACTURER），接收输入
Step 1  读统一标签库 schema（不存在则初始化 v1.0）
Step 2  通读报告，识别对象特征语句/字段
Step 3  穷举核对 D0-D5（或 M1-M6）全部分类（不遗漏）
Step 4  提取归位（match_behavior/main_control/priority）
Step 5  词表对齐（品类/品牌规范化，dict_alias 记原文词）
Step 6  质量评分（5 锚点）→ confidence（含时效衰减）
Step 7  完整性评分（双层+加权）
Step 8  生成 MD 报告 + 对象 JSON 数据块
Step 9  ≥85 交付；60-85 列清单降级交付；<60 暂停请求补充
Step 10 落地：MD→exports；upsert 入库；Schema 演进检查（候选→判断特例/可推广→新增/调整/不动→升版本+changelog）；回写 frontmatter；数据资产建议
```

退出条件：用户声明无更多补充→降级交付，UNCOVERED 标"信息不可得，非执行遗漏"；补充轮次上限 2 轮，超限降级标"待数据补齐后重跑"；无采集渠道→标"不适用"不请求。

## 十五、硬性约束（红线）

1. 禁止虚构：画像未出现的信息只能标 UNCOVERED（不出 schema）或 COVERED_WITH_HEURISTICS（≤0.6）。
2. 层级≤4 层；受控词表+OTHER 兜底。
3. 穷举检查、精选输出：单对象 COVERED ≤40 条（P0+P1≤25，P2≤15），超出进候选池不进主报告。
4. 评分强制：所有 COVERED 必须有 quality_score 与 confidence_score；体系必须有完整性评分。
5. 撮合纪律：GATE/WEIGHT 分离；自动撮合只消费 ≥0.6；GATE 排除注明粒度。
6. 用户介入：补充请求仅限"有采集渠道但画像未写"；无渠道标"不适用"；最多 2 轮。
7. 输出完整：报告（十二）+ JSON 入库（八）缺一不可。
8. 时效与冲突：as_of_date/source_report_id 必填；冲突裁决见下节。

## 十六、时效与冲突裁决

裁决优先级：用户当前确认口径 > 最新报告（生成时间） > 汇总表/底表 > 推断。涉及"当前状态"标签（D0.2 合作状态/在供品类）以用户口径为准，画像未列在供品类标【待盘点】而非"无实证"。多版本矛盾→以 as_of_date 最新为准，冲突标签 confidence 降级+强制人工审核（PENDING_CONFIRM）。刷新建议：静态（D0-D2）半年复核；动态（D3/D4.1/D5）季度复核或随新报告重打。

## 十七、调用约定

触发：为新的客户/原厂画像报告打标签、建立/更新标签库、更新标签字典时调用。输入：画像报告+可选交易数据/CRM。输出：每对象 MD 报告 + 统一标签库增量 upsert。阻塞：完整度<60 暂停请求补充；60-85 且无法补充→降级交付标"部分完整，已知缺口"。联动：sales-transaction-diagnostics（交易数据）、authorized-product-line-reference（词表）、product-line-opportunity-matching / customer-group-analysis（下游消费）、customer-profiling / manufacturer-profiling（画像生产）。

## 十八、术语表（速查）

穷举检查=内部核对全部分类不遗漏（≠穷举输出）；统一标签库=全库唯一客户标签库.json（schema+objects 同库）；Schema 演进=新维度→判断→调整→升版本闭环；GATE/WEIGHT=硬筛/策略切换 vs 加权打分；主控/外围=平台锁定件（原厂直采）vs 分销切入面；待盘点=画像未列在供品类占位标记（数据盲区，非状态判定）；OTHER 兜底=词表外新值统一记 OTHER；RFM=最近采购/频率/金额（衍生分层）；D3X=外部行为扩展轨（不参与完整度评分）；COVERED/HEURISTICS/UNCOVERED=明确可承载/启发式推导(≤0.6)/未提供；撮合=客户或原厂标签×授权产品线匹配→可执行销售动作。
