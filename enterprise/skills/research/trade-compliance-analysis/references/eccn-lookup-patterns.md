# ECCN 实战查询模式（实践积累）

## 核心问题：搜索结果 vs 原文提取

DuckDuckGo 作为搜索后端，web_extract 不可用。ECCN 信息依赖**搜索结果摘要中的分销商标注**。

## 最有效的 ECCN 检索模式

### 模式 A：分销商搜索（首选）
```
site:element14.com "[完整型号]" US ECCN
site:newark.com "[完整型号]" ECCN
site:farnell.com "[完整型号]" ECCN
site:digikey.com "[完整型号]" ECCN
site:mouser.com "[完整型号]" ECCN
```
element14/Newark/Farnell 的产品页会在搜索结果摘要中直接显示 `US ECCN:3A991.d` 格式的文本。DigiKey/Mouser 的摘要通常不含 ECCN。

### 模式 B：聚合平台搜索
```
site:fpgakey.com "[型号]" ECCN
site:octopart.com "[型号]" ECCN
site:findchips.com "[型号]" ECCN
```
fpgakey.com 常在摘要中标注 ECCN Code 字段。

### 模式 C：厂商官网搜索
```
site:latticesemi.com "[型号]" ECCN export
site:ti.com "[型号]" ECCN export classification
```
制造商官网有时在出口合规页面标注 ECCN 归类。

### 模式 D：泛搜索（兜底）
```
"[完整型号]" ECCN
"[完整型号]" export classification
"[完整型号]" EAR99
```

## 常见芯片类型 ECCN 归类模式

### FPGA / CPLD
| 类型 | 典型 ECCN | 推断依据 |
|------|-----------|---------|
| 高端 FPGA（Virtex/Kintex/Agilex/Stratix） | 3A001.a.7 | 高性能可编程器件，受 NS/MT 管制 |
| 中端 FPGA（Artix/Cyclone/MachXO3L 等低密度） | 3A991.d 或 EAR99 | 非 3A001 受控的通用 FPGA |
| 低密度 CPLD/PLD（MachXO2/3, ispMACH） | EAR99 | 功能简单、逻辑密度低 |
| Lattice iCE40 | 3A991 | 经 element14/Newark 验证 |
| Lattice ECP5 | 3A991D | 经分销商验证 |
| Lattice MachXO3 系列 | EAR99 或 3A991.d | fpgakey/futureelectronics 标注 |

### 模拟 IC / 电源管理 / 接口
| 类型 | 典型 ECCN | 推断依据 |
|------|-----------|---------|
| 通用电源管理 IC（LDO/DC-DC） | EAR99 | 民用等级 |
| 通用接口 IC（RS-232/485/CAN） | EAR99 | 民用等级 |
| 高性能 ADC/DAC（>1Gsps） | 3A001.a.5 | 高速转换器管制 |
| 普通 ADC/DAC | EAR99 | 民用等级 |

### 存储器
| 类型 | 典型 ECCN | 推断依据 |
|------|-----------|---------|
| 通用 DRAM/NAND/NOR Flash | EAR99 | 民用标准 |
| 高端 DDR5/LPDDR5（特定容量以上） | 可能受 EAR §744.23 限制 | 针对中国的先进计算限制 |
| 普通 SRAM/EEPROM | EAR99 | 民用标准 |

## ECCN 三档速查逻辑

1. **3A001**：高性能/受 Wassenaar 管控的先进器件 → 需许可
2. **3A991**：非 3A001 但列在 CCL 上的器件 → 仅 AT 受控，对中国出口通常低风险
3. **EAR99**：未列入 CCL → 无特殊许可要求（但须关注最终用户/用途）

> **重要**：对于 3A991 和 EAR99 的区别，在实际合规操作中对中国目的地影响不大——两者均只需要确认最终用途和最终用户清洁即可。

## 中国公司背景验证站点

| 站点 | 用途 | 搜索方式 |
|------|------|---------|
| qcc.com (企查查) | 查公司工商信息、经营范围 | `site:qcc.com [公司全名]` |
| aiqicha.baidu.com (爱企查) | 同上，不同数据源交叉验证 | `site:aiqicha.baidu.com [公司全名]` |
| tianyancha.com (天眼查) | 同上 | `site:tianyancha.com [公司全名]` |

通过工商信息判断业务性质（是否涉及军事/敏感领域）。

## 已实践验证的案例

### 案例：LCMXO3LF-2100C-5BG256C（Lattice MachXO3 FPGA）
- ECCN 认定：EAR99（基于同系列 LCMXO3L-2100 在 fpgakey/futureelectronics 的标注）
- 推理逻辑：2112 LUTs, 低密度, 非加密, 65nm → 远低于 3A001 管控阈值
- 来源置信度：⚠️ Partial（分销商页面，非 BIS 官方 CCL）
- 最终判定：大概率 EAR99，最坏情况 3A991.d（均低风险）

### 案例：LCMXO1200C-4FTN256C
- ECCN 认定：3A991D（element14 标注 "US ECCN:3A991D"）
- 来源置信度：⚠️ Partial（分销商页面）
