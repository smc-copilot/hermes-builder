# 上市公司财务数据检索指南

> 用于客户画像阶段一（市场地位与规模检索）、阶段二（供应链采购检索）的数据源优选顺序和搜索策略。

## 数据源层级（按可靠性排序）

### 第一层级：官方一手来源

| 数据源 | 适用公司类型 | 查询方向 | 特点 |
|--------|-------------|----------|------|
| **公司官网 Investor Relations 页面** | 全部上市/大型公司 | `[公司.com]/investors/` 或 `[公司.com]/zh-TW/investors/` | 最准确，含Chairman's Statement、财务摘要、年报PDF |
| **TWSE 公开资讯观测站 (MOPS)** | 台湾上市公司 | `mops.twse.com.tw` | 台股公司法定披露平台，含原始财报 |
| **SEC EDGAR (20-F/6-K)** | 在美上市ADR | `sec.gov/cgi-bin/browse-edgar` | 美股标准格式，便于比较 |
| **港交所披露易 (HKEX News)** | 香港上市公司 | `hkexnews.hk` | 港股公司法定披露 |

### 第二层级：专业财经数据平台

| 数据源 | 查询方式 | 优势 | 局限 |
|--------|----------|------|------|
| **StockAnalysis** | `stockanalysis.com/quote/[交易所]/[代码]/revenue/` | 多年营收趋势图、报表数据结构化 | 部分公司数据不完整 |
| **SimplyWallSt** | `simplywall.st/stocks/[交易所]/[行业]/[代码]/` | 含估值分析、财务比率、可视化 | 免费版功能有限 |
| **CompaniesMarketCap** | `companiesmarketcap.com/[公司名]/revenue/` | 营收规模速查、同行对比 | 仅营收数据 |
| **Yahoo Finance** | `finance.yahoo.com/quote/[代码]/` | 收益电话会转录(Transcript) | 广告多、页面重 |
| **TradingView** | `tradingview.com/symbols/[交易所]-[代码]/` | 分析师报告、财报摘要 | 高级功能需付费 |
| **BigGo Finance (台湾)** | `finance.biggo.com` | 台股即时新闻 | 数据颗粒度有限 |

### 第三层级：搜索引擎直接检索

当官方和财经平台数据不足时：

- `[公司全称] annual report [年份] revenue` 或 `[公司全称] [年份]年 年报`
- `[公司全称] [年份] 营收 毛利率 营业利益`
- 搜索时用英文公司名+英文关键词通常比纯中文搜索更干净

---

## 搜索查询模板库

### 财务数据检索

```
# 情景A：已知TWSE/A股公司代码
{代码}.TW revenue {年份}   # 台股
{代码}.SZ revenue {年份}   # 深交所
"stockanalysis.com/quote/tpe/{代码}"

# 情景B：仅知公司名（大型公司）
"{公司英文名}" annual report {年份} revenue
"{公司英文名}" "{年份}" gross margin net income
"{公司英文名}" investor relations financial highlights

# 情景C：台资公司中文搜索
{公司名} {年份} 年营收 毛利率
{公司名} {年份} 合并财务报表
```

### 供应链数据检索

```
# 采购规模估算（从COGS倒推）
"{公司名}" cost of goods sold {年份}
"{公司名}" COGS procurement
"{公司名}" 营业成本 {年份}

# 制造基地
"{公司名}" factory manufacturing site
"{公司名}" 工厂 生产基地 {地点词:昆山/东莞/吴江}

# 供应商关系
"{公司名}" supplier partner distribution
"{公司名}" 供应商 合作 代理 Arrow Avnet WPG
```

### 管理层/组织架构检索

```
# 高管团队
"{公司名}" management team executive
"{公司名}" 管理团队 executive board
"{公司名}" 总裁 总经理 CEO

# 采购决策人
"{公司名}" purchasing procurement supply chain VP
"{公司名}" 采购 总监 VP 供应链
```

---

## 搜索效果优化原则

### 1. 先英后中

对于所有跨国公司、台湾/香港上市公司、海外品牌：
- **第一轮**：用英文公司全称 + 英文关键词（`Delta Electronics annual report 2025`）
- **第二轮**：用中文公司全称 + 中文关键词补充（`台达电子 2025 年报 营收`）
- **理由**：英文搜索返回的财经站点信息密度远高于中文搜索，噪声更低

### 2. 按代码搜索优于按名称搜索

- `stockanalysis.com/quote/tpe/2308/revenue/` 比 `台达电子 2025 营收` 更准确、更结构化
- Yahoo Finance 的 `2308.TW` 页比中文搜索得到的零散新闻更可靠

### 3. 收益电话会转录（Earnings Call Transcript）是金矿

Yahoo Finance 的 Earnings 页面下通常有历年收益电话会转录文本，含有：
- 管理层对业务的定性分析（"AI power demand surge"）
- 各业务分部的定量数据（"Infrastructure segment profit up 287%"）
- 前瞻性指引（"expected growth next quarter"）
- 这些数据在搜索引擎快照中不出现，需从公司IR页面或Yahoo Finance直接获取

### 4. 搜索词组合策略

不要只搜一次。对同一个数据点，用3种不同角度搜索：

```
# 角度1：平台数据
"stockanalysis.com delta electronics revenue"

# 角度2：公司官方
"deltaww.com chairman statement revenue"

# 角度3：行业新闻
"Delta Electronics reports Q4 2025 revenue NT$"
```

### 5. 中文搜索去噪技巧

当中文公司名+行业关键词搜索返回大量垃圾站点时：
- 使用引用号精确匹配（`"台达电子" "营收" "2025"`）
- 增加排除词（`-招聘 -推广 -客服`）
- 换用英文公司名+英文关键词代替
- 优先访问 site:baike.baidu.com 或 site:deltaww.com 等已知权威域名

---

## 财务数据从COGS到元器件采购规模的推算公式

| 步骤 | 公式 | 说明 |
|------|------|------|
| 1. 毛利率 → COGS | COGS = 营收 × (1 - 毛利率) | 毛利率从财报获取 |
| 2. COGS → 元器件采购 | 采购 ≈ COGS × 60%~70% | 电子产品制造行业经验值 |
| 3. 年采购量 → 1%份额 | 年交易额 = 采购 × 1% | 用于计算首年合作目标 |

> **标注要求**：步骤2和3的结果必须标注「推算/估算」并在附注中说明口径依据。
