# 无线通信芯片参数采集框架（Wireless/Communication IC Parameters）

当文案对象为Wi-Fi芯片、蓝牙SoC、蜂窝通信模组等无线通信IC时，使用本框架替代默认IC参数模板（工作电压/静态电流/传播延迟等不适用于此类器件）。

## Wi-Fi芯片核心参数集

按以下维度采集和呈现，顺序从高代际到低代际：

| 参数维度 | 说明 | 示例 |
|---------|------|------|
| 无线标准 | IEEE标准号 + 商业名称 + 向下兼容性 | IEEE 802.11be（Wi-Fi 7），向下兼容a/b/g/n/ac/ax |
| 频段支持 | 具体频段列举 | 2.4GHz + 5GHz + 6GHz三频段 |
| 信道带宽 | 最大支持值（区分不同代际的关键参数） | 最大320MHz / 160MHz / 80MHz |
| PHY层速率 | 商业标称 + 各频段拆解 | BE6500（2.4GHz 688Mbps + 5GHz 2882Mbps + 6GHz 2882Mbps） |
| 调制方式 | 最高阶QAM | 4096-QAM / 1024-QAM / 256-QAM |
| 天线配置 | MIMO规格 | 2×2 MIMO / 4×4 MIMO / 2T2R |
| 核心特性 | 协议级关键技术（非通用描述） | MLO、MRU、AFC、OFDMA、TWT、BSS Coloring |
| 蓝牙版本 | 具体版本号 + 关键特性 | Bluetooth 5.4（支持LE Audio） |
| 接口形式 | 物理接口标准 | M.2 Key E / M.2 2230 / PCIe / SDIO / USB |
| 封装形式 | 模组级封装（非裸片） | M.2 2230模组 / QFN-68 |

## Wi-Fi代际速查（用于阶段二快速校验）

| 代际 | 标准 | 商业名 | 最高调制 | 最大带宽 | 关键新特性 |
|------|------|--------|---------|---------|-----------|
| Wi-Fi 7 | 802.11be | BE+速率 | 4096-QAM | 320MHz | MLO、MRU、AFC |
| Wi-Fi 6E | 802.11ax | AX+速率 | 1024-QAM | 160MHz | 6GHz频段 |
| Wi-Fi 6 | 802.11ax | AX+速率 | 1024-QAM | 160MHz | OFDMA、TWT、BSS Coloring |
| Wi-Fi 5 | 802.11ac | AC+速率 | 256-QAM | 80MHz/160MHz | MU-MIMO（下行） |

## 蓝牙版本速查

| 版本 | 关键特性 | 常见搭配Wi-Fi代际 |
|------|---------|-----------------|
| BT 5.4 | LE Audio、Auracast广播 | Wi-Fi 7 |
| BT 5.3 | 信道分类增强、LE Audio | Wi-Fi 6E |
| BT 5.2 | LE Audio基础、EATT | Wi-Fi 6 |
| BT 5.1 | 寻向特性、BLE双模 | Wi-Fi 5 |
| BT 5.0 | 2Mbps LE、长距离 | Wi-Fi 5 |

## 速率命名规则

- Wi-Fi 7: BE + 聚合速率（如BE6500 = 6500Mbps三频合计）
- Wi-Fi 6: AX + 聚合速率（如AX1800 = 1800Mbps双频合计）
- Wi-Fi 5: AC + 聚合速率（如AC1200 = 1200Mbps双频合计）

## 多型号产品线选型文案场景

当同一篇文案覆盖同一品牌多颗Wi-Fi芯片（跨代际）时：
- 产品详情按Wi-Fi 7 → Wi-Fi 6 → Wi-Fi 5顺序排列
- 每颗型号的核心差异化参数必须明确标注（如"320MHz带宽"vs"160MHz带宽"是MT7927与MT7925的关键差异）
- 应用场景按终端产品定位分层：旗舰设备→主流设备→入门设备→IoT/嵌入式
- 避免在应用场景中使用"适用于所有场景"的笼统描述

## 蜂窝通信模组参数集（扩展用）

| 参数维度 | 说明 |
|---------|------|
| 通信制式 | 5G NR / LTE Cat.x / NB-IoT / Cat-M1 |
| 频段支持 | 具体频段编号（如n78/n41/B3/B7） |
| 下行/上行速率 | 理论峰值 |
| SIM卡接口 | eSIM / Nano-SIM / MFF2 |
| 定位模块 | GPS/BDS/GLONASS/Galileo |
| 工作温度 | 工业级（-40~+85°C）vs 消费级 |
| 封装/尺寸 | LGA / M.2 / Mini PCIe |

> 注意：蜂窝模组参数与本文件Wi-Fi参数集差异显著，不可混用。
