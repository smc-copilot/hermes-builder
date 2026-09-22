# 客户画像 PPT 报告生成指南

> 2026-08 验证通过。将客户画像 Markdown 报告转换为专业 PPT 的标准流程。

## 前提条件

- `node` + `npm` 可用
- 项目目录下安装：`npm install pptxgenjs react-icons react react-dom sharp`
- 如 `react-icons`/`sharp` 不可用，见下方降级策略

## 标准结构（10-12 页）

基础10页为标配。当用户要求组织架构图或产品硬件框图（如"机顶盒PCBA框图"）时，在第2页后插入扩展页：

| 页码 | 内容 | 关键元素 |
|:----:|------|---------|
| 1 | **封面** — 公司名 + 评级 + 关键数据 | 深海军蓝底 + 金色点缀 |
| 2 | **公司概览** — 基本信息表 + 核心亮点卡片 | 左侧表格 + 右侧数字大卡片 |
| 2+ | **（可选）组织架构图** — 层级树形结构 | 矩形节点 + 连线 + 四级颜色区分 |
| 2++ | **（可选）产品硬件框图** — PCBA/系统架构 | SoC居中 + 外围模块 + 箭头连线 + BOM表 |
| 3 | **核心产品矩阵** — 业务线 2×2 / 2×3 卡片 | 彩色顶条卡片 |
| 4 | **芯片需求核心推荐** — ★★★ 确定品类 + 品牌 | 编号圆形 + 深蓝品牌标签 |
| 5 | **品牌匹配亮点** — 授权品牌矩阵 | 2×3 品牌卡片网格 |
| 6 | **扩展机会清单** — ★★☆ 可能品类表格 | 标准三列表格 |
| 7 | **量化评分** — 大分数 + 三维度进度条 | 左侧大"A"等级 + 右侧进度条 |
| 8 | **竞品格局与差异化** — 8维对比表 | 我方列绿色高亮 |
| 9 | **切入策略与行动建议** — 三步路径 + 时间线 | 圆形编号步骤 + 4阶段时间轴 |
| 10 | **总结与风险提示** — 核心结论 + 风险关注 | 深底半透明三列卡片 |

> **组织架构图实现**：使用 `addShape('rect')` + `addShape('line')` 构建层级节点。标准四级结构：集团母公司 → 上市/控股主体 → 核心子公司(4家) → 职能部门(7个)。每级不同配色（深海军蓝→浅卡片白）。连线统一用 navy 色 1.2pt 线。
>
> **PCBA/硬件框图实现**：中央大矩形放置 SoC（深海军蓝底+白色文字+具体型号列表），周围 8-10 个小型功能块（DDR/eMMC/PMIC/WiFi/ETH/HDMI/Tuner/USB/Audio/IR），用箭头线连接。每个功能块白色底+彩色顶条+品类标题+具体型号。底部附加 BOM 供应商对照表（4列：类别/器件/主要品牌/推荐替代）。参考实现见本 session 的 `build_skyworth_ppt.js` PCBA slide 代码段。

## 配色方案

### 方案一：Midnight Executive（默认，深色专业风）
| 用途 | 色值 | 名称 |
|------|------|------|
| Primary | `1E2761` | 深海军蓝 |
| Dark variant | `151D4A` | 更深夜蓝（封面底） |
| Secondary | `CADCFC` | 冰蓝（副标题/正文亮色区） |
| Accent | `F0B429` | 金色（关键数字/分隔线） |
| Light BG | `F5F7FA` | 浅灰底（内容页背景） |
| White | `FFFFFF` | 卡片/表格底色 |
| Table header | `1E2761` | 表头深蓝 |
| Table stripe | `EBF0FA` | 表格交替行 |

### 方案二：Sky Blue + White（淡蓝色+白色，清新明亮风）

> 适用场景：用户要求"淡蓝色+白色""清新""明亮商务风"等。用户明确指定颜色偏好时优先采用。

| 用途 | 色值 | 名称 |
|------|------|------|
| Primary | `5B9BD5` | 天空蓝（标题/重点色） |
| Dark variant | `4A90D9` | 较深天空蓝（封面背景） |
| Secondary | `D6EAF8` | 极浅蓝（副标题/淡色文字区） |
| Accent | `F0B429` | 金色（关键数字/分隔线，保留） |
| Light BG | `F5F9FD` | 蓝调白底（内容页背景） |
| White | `FFFFFF` | 卡片/表格底色 |
| Table header | `4A90D9` | 表头天空蓝 |
| Table stripe | `EBF3FB` | 表格浅蓝交替行 |
| Dark text | `2C5282` | 深蓝文字（替代原navy文字色） |

> **切换提示**：两个方案的 JS 脚本结构完全一致，仅 `C = {...}` 颜色对象的 hex 值不同。从 Midnight Executive 切换到 Sky Blue 只需替换颜色常量。但注意 Sky Blue 方案下封面 `transparency` 需从 92 调整为 80（浅色底上半透明白色卡片需要更低的透明度才能保证可读性）。

## 图标

使用 `react-icons/fa`（Font Awesome），通过 `sharp` 转换为 PNG base64。关键代码模式：
```javascript
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const { FaBuilding, FaMicrochip, FaChartBar, FaShieldAlt, FaRocket, FaBullseye, FaUserTie, FaHandshake, FaExclamationTriangle } = require("react-icons/fa");

function renderIconSvg(IconComponent, color = "#000000", size = 256) {
  return ReactDOMServer.renderToStaticMarkup(
    React.createElement(IconComponent, { color, size: String(size) })
  );
}
async function iconToBase64Png(IconComponent, color, size = 256) {
  const svg = renderIconSvg(IconComponent, color, size);
  const pngBuffer = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + pngBuffer.toString("base64");
}
```

## PptxGenJS 关键约定

1. **颜色不用 `#`** — 所有十六进制颜色去掉 `#` 前缀
2. **Shadow 必须每次新建** — 不能复用 option 对象（PptxGenJS 内部会 mutation）
3. **`breakLine: true`** — 多行文本数组必须用
4. **`bullet: true`** — 不用 Unicode 符号
5. **中文字体** — `fontFace: "Arial"` 在大多数系统上能正常渲染中文
6. **⚠️ 中文引号陷阱** — JS字符串中使用中文双引号 `"` `"`（U+201C/U+201D）会与JS字符串分隔符冲突导致 SyntaxError。处理方式：①将外层JS引号改用单引号 `'...'` 包裹含有中文双引号的字符串，或②使用 `\u201C` / `\u201D` Unicode转义。编译前用 `node --check` 验证语法。此陷阱在高频出现在免责声明、备注、数据标注等中文文本中。

## 执行流程

1. 在客户画像阶段六 MD 报告生成后，检查是否已有 `{公司简称}_客户画像报告.md`
2. **推荐路径（从零构建）**：参照本指南的12页结构 + `pptx` skill 的 `pptxgenjs.md` 中的代码模式，在 `workspace/scripts/build_{公司}_ppt.js` 中编写完整生成脚本。脚本中直接内联公司数据（无需占位符模板），运行 `node scripts/build_{公司}_ppt.js`。
3. **备用路径（模板驱动）**：加载 PPT 模板，将 `{{PLACEHOLDER}}` 替换为关键数据后运行。注：模板可能因版本差异不兼容，优先使用路径2。
4. 输出到 `exports/YYYYMMDD_公司简称_客户画像报告.pptx`

> **从零构建最佳实践**：
> - 将配色、图标 helper、阴影 helper、addCard/addPageTitle 等通用函数放在脚本顶部
> - 每个 slide 用 `{ }` 代码块封装，便于定位和修改
> - PCBA 框图和组织架构图的形状坐标使用精确 x/y 定位，以 0.1" 为精度单位
> - 生成前用 `node --check` 验证语法，特别注意中文引号问题（见上方 PptxGenJS 关键约定第6条）
> - **参考实现**：本仓库 `workspace/scripts/build_skyworth_ppt.js` 是一个已验证通过的12页完整脚本，包含组织架构图 + PCBA框图 + 品牌矩阵 + 量化评分 + 竞品对比 + 切入策略等所有核心模块。为新客户生成PPT时可直接复制其结构，替换公司数据和SoC型号即可。

## 输出约定

```
/data/hermes/workspace/exports/YYYYMMDD_公司简称_客户画像报告.pptx
```

## 降级策略

如果 `react-icons` 或 `sharp` 不可用（如 npm install 失败），回退为无图标纯文本+形状方案：
- 用 `addShape('oval', ...)` + 数字替代圆形图标
- 用 `addShape('rect', ...)` 的彩色 accent bar 作为视觉锚点
- 色值和布局保持不变
