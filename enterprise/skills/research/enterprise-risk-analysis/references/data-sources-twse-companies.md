# TWSE（台湾证券交易所）上市公司研究数据源

> 用于企业风险评估第1-2轮搜索（企业画像 + 财务数据），当目标公司为台湾上市公司时优先使用。

## 官方披露渠道

| 数据源 | 网址 | 可用数据 | 说明 |
|--------|------|----------|------|
| **公开资讯观测站（MOPS）** | https://mops.twse.com.tw/ | 年报、季报、月营收、重讯 | TWSE官方披露平台，有中文/英文版 |
| **公司官网投资者关系** | `公司域名/investor` 或 `公司域名/en-us/investor` | 年报PDF、法说会简报、ESG报告 | 通常提供最完整的PDF年报（英文），可直接用web_search + PDF链接提取财务数据 |

## 第三方财务数据平台

| 数据源 | 网址 | 可用数据 | 说明 |
|--------|------|----------|------|
| **WSJ Market Data** | https://www.wsj.com/market-data/quotes/TW/XTAI/{代码}/financials | 资产负债表、损益表、现金流（年度） | 结构化呈现，摘要中常含关键指标描述 |
| **Simply Wall St** | https://simplywall.st/stocks/tw/tech/twse-{代码}/ | 财务健康评分、EBIT、现金、负债 | 含一键财务健康判读（6/6检查） |
| **Stock Analysis** | https://stockanalysis.com/quote/tpe/{代码}/financials/ | 多年度财务数据表 | 结构化年度/季度财务数据 |
| **Yahoo Finance Taiwan** | https://tw.stock.yahoo.com/quote/{代码}.TW | 实时股价、财报、财务比率 | 台湾用户常用，中文界面 |
| **Bloomberg** | https://www.bloomberg.com/quote/{代码}:TT | 公司概况、关键人物、财务摘要 | 管理层姓名和职务信息 |
| **GuruFocus** | https://www.gurufocus.com/stock/TPE:{代码}/summary | 估值指标、财务比率 | 含历史财务趋势 |
| **CompaniesMarketCap** | https://companiesmarketcap.com/{品牌名}/ | 营收、市值、净资产 | 简洁的摘要数据 |
| **Alpha Spread** | https://www.alphaspread.com/security/twse/{代码}/ | 投资者关系摘要、营收和净利记录 | 含季度突破性数据 |

## 行业与市场数据

| 数据源 | 网址 | 可用数据 | 说明 |
|--------|------|----------|------|
| **PitchBook** | https://pitchbook.com/profiles/company/{ID} | 公司档案：员工、HQ、行业分类 | 基本信息核对 |
| **EMIS** | https://www.emis.com/ | 公司档案：员工数、成立年份、营收 | 含成立日期精确到日 |
| **IPC2U / Accio** | 行业垂直站点 | 市场地位、市占率排名 | 如"Advantech holds the largest global market share in IPC" |

## 搜索策略备忘录

### 推荐搜索顺序

1. 先用 `"{公司英文名}" annual report 2024` 或 `"{公司英文名}" "annual report" PDF` 找到官方年报PDF链接
2. 用 `site:tw.stock.yahoo.com "{代码}"` 获取台湾本地市场数据
3. 用 `"{代码}" "total assets" "NT$"` 获取财务数据的具体数值（年报摘要中常含关键数据）
4. 用公司英文名 + 财务指标词（如 "Advantech" "gross profit" "operating cash flow"）补充

### 货币单位

TWSE公司使用**新台币（NT$ / NTD）**。营收和利润数据单位可以是"千元"（thousands）或"百万元"（millions），需注意单位换算。

换算参考：US$1 ≈ NT$32（2025年汇率）

### 关键财务指标获取

| 指标 | 常用搜索短语 |
|------|-------------|
| 营收 | `"{代码}" revenue` 或 `"{品牌}" consolidated revenue` |
| 毛利率 | `"{品牌}" "gross profit" margin` |
| 经营现金流 | `"{品牌}" "operating cash flow"` |
| 总资产/负债 | `"{品牌}" balance sheet total assets` |
| 资产负债率 | `"{品牌}" "debt ratio"` 或 `"{代码}" liabilities to assets` |
| 现金流/营收比 | 需要自己计算：CFO / Revenue |
| 员工数 | `"{品牌}" employee` 或 PitchBook/EMIS |
