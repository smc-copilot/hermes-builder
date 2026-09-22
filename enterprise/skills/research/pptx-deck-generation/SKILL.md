---
name: pptx-deck-generation
description: "报告/数据/画像→.pptx：客户画像推广/经营数据汇报/行业知识培训/规则宣贯四类。触发：把客户画像做成PPT、季度/半年/年度业务数据做PPT、行业培训PPT、把这个报告做成PPT、做XX培训PPT、convert data to slides。公司模版优先，卡片化图形版式+结构化QA。"
version: 2.6.7
category: research
---

# PPT Deck Generation（报告/数据分析 → .pptx）

> v2.6.7 = v2.6.6 补 A 型「充实建议」(骨架是下限非上限，主动补产品/行业/差异化能力页，避免「内容过于简洁」)。v2.6.6 = v2.6.5 修复(用户偏好 2026-09)：①全文默认字体统一「微软雅黑」(思源黑体非 Windows/WPS 预装→方框风险)，§0/§6.2 改；②子页标题**左对齐**+深蓝`0B3D7A`(仅封面居中)；③增 `normalize_fonts()` 统一模版自带思源文字。v2.6.5 已增 CJK 方框(缺 a:ea)陷阱 + `_set_ea`；v2.6.4 已增孤儿 slide 部件陷阱、`add_slide('Logos')` 是 logo 墙、`clean_template`/`duplicate_content_slide`。自包含，§6 代码与关键数据保留。

## 术语
- **总页数**=含封面/Thanks｜**C**=总页数−2｜**固定页**=恒保留｜**弹性页**=随内容增减，少可低于下限、**禁凑数**｜**建议带**=§2区间非硬限
- **渲染验证**=soffice→PDF→pdftoppm目检｜**结构化QA**=python-pptx边界+PIL度量+关键词抽查(不含视觉)｜**视觉元素**=图表/卡片/装饰，默认建议项非强制
- **简单文字页**=附录/数据明细表/术语表/纯文字说明等非主视觉页，用线性h/p/gap排版(标题/段落/间距)，不载图表

## 0. 公司模版优先（强制）
默认模版 `assets/芯智控股_PPT模版.pptx`（芯智控股 02166.HK，3 页）。绝对路径 `/data/hermes/skills/research/pptx-deck-generation/assets/芯智控股_PPT模版.pptx`。模版存在→默认走 company-ppt-template（操作见 §6.1）；用户指定其他模版→同流程；仅明确「自由设计/不用公司模版」或模版缺失→§3.1。
区间=**建议带**：内容复杂贴近上限；突破 +5 页先确认；内容少可低于下限（禁凑数）。

### 模版结构（生成前必读，16:9=13.333×7.5in）
| 页 | 版式名 | 内容 |
|---|---|---|
| 封面 | 标题和内容 | 右上logo+股票码「02166.HK」｜中部主标题框(占位「替换标题名称」思源黑体48pt加粗)+分隔线｜底部4应用图+右下「AI引领未来」｜蓝金双色带页脚 |
| 内容页 | Logos | 左上小logo+标题占位「PPT页面标题」(思源黑体Heavy)+右上logo｜正文区待填｜蓝金双色带页脚 |
| 结尾 | 2_Blank | 全幅背景图+「Thanks」(Arial Black)+圆形logo+「止于至善，追求卓越！」｜蓝金双色带页脚 |

**品牌色**：主蓝`006CB5`/深蓝`0062A4`/`005C9A`｜金`FBB130`｜logo绿`27B484`。**字体**：思源黑体(CN Regular/Normal/Heavy)+结尾Arial Black。**蓝金双色带页脚(蓝`006CB5`+金`FBB130`)为品牌核心识别，新增页必须保留。**

**字体统一偏好(用户定，2026-09)**：交付客户/对外的 PPT **全文默认字体统一用「微软雅黑」**(Microsoft YaHei)，**不用思源黑体**——思源黑体非 Windows/WPS 预装，缺失时中文显示方框/字体回退异常；微软雅黑为 Windows/WPS 通用中文字体，macOS 自动回退苹方(PingFang SC)。生成末尾跑 `normalize_fonts()`(见§6.2)把模版自带思源文字也一并替换。仅「Thanks」保留 Arial Black(拉丁设计字体)。

## 1. 触发
A 客户画像→客户演示推广PPT｜B 季/半年/年度业务数据(先出报告)→内部报告会PPT｜C 行业/产业研究报告→内/外培训PPT｜D 制度/评分/操作文档→宣贯PPT｜通用「做成PPT」「汇报材料」「deck」「presentation」。

## 1.5 视觉布局总则（强制：全页图文·图形化·一目了然）
适用于四类+兜底，优先于模板默认：
- **全页展示**：正文区(y≈1.3–7.2)铺满，每页=标题+图形化正文；禁半页留白/整页文字堆叠
- **图像化**：数据/清单/要点用图形承载(卡/色块/徽标/色条/箭头/图表)，文字只作补充
- **框架显逻辑**：内容关系定版式(见版式库)——流程用节点+箭头、链路用环节图、总分用网格、对比用双色卡
- **图文并茂**：每页≥1图形版式+适量文字；有图素材优先用图
- **一目了然**：每页一主题；标题≤18等效中文字且表主题/结论；卡文字≤2行/块

**版式库（python-pptx定制，helpers见§6.2）**：
| 内容 | 版式 |
|---|---|
| 议程/模块总览 | 网格卡2×2/2×3+圆徽编号 |
| 并列要点/画像 | 双栏/多栏信息卡 |
| 流程/步骤 | 横节点卡+金箭头(RIGHT_ARROW) |
| 链路/架构 | 环节链路图(节点+箭头+结论条) |
| 清单/品牌/器件 | 矩阵chips或斑马横条卡 |
| 对比/正反 | 蓝/金双色对比卡 |
| 结论/承诺 | 全宽深蓝底白字或浅金结论条 |
| KPI | 大数字卡(60–72pt+小标签) |
| 模块归属 | 卡顶/侧蓝金细条+圆徽01–06 |

**纪律**：主视觉页一律python-pptx定制；线性h/p/gap仅限简单文字页(见术语)；坐标全显式(x/y/w/h)；元素注册后逐页隔离自检(§6.3)。

## 2. 类型→框架注册表（核心配置位，增改类型只改本表）
格式：固定页+弹性页=总页数(建议带)。顺序：识类型→取骨架→按映射示例映射源章节→每页一主题→按§1.5选版式→生成(禁文字墙)。示例①②仅演示映射逻辑，真实章节以文件为准。

### A. 客户画像推广型(customer-profile-promo)
输入：客户画像(需求×授权线契合)；目的：客户演示「你懂我、你能配」。
固定(7)：封面←客户名+主题｜议程｜认知篇←贵司行业地位/主营/市场表现(正面复述)｜需求篇←业务场景与潜在需求(按产品归因)｜我司篇←简介+授权线(只列相关线)｜服务支持←FAE/样品/交付/质量｜Thanks。
弹性(1–7)：契合方案1–6(点少→1页总表「需求→方案/器件→价值」；点多→每点1页)+合作展望0–1。
总页数8–14。
纪律：全程正面，**禁内部评级/评分/风险/金额预判**；客户名贯穿；「懂客户」>「推产品」；每页建议≥1客户语境视觉。
映射：①公司概况+②主营市场→认知篇；③采购场景+④供应链痛点→需求篇；⑤可匹配产品线→我司篇；③×⑤→弹性页；封面/议程/Thanks照骨架。
**充实建议(2026-09「内容过于简洁」反馈，骨架是下限非上限)**：源报告有料时主动充实，禁只铺最简骨架——①认知篇可拆出「产品与技术实力」页(产品矩阵6卡+技术平台+自研能力条)；②需求篇可配套「行业机遇」页(市场规模/趋势/政策驱动/客户转型窗口，如「17.4亿美元全球公共广播市场」)；③服务页补差异化能力(EOL预警管理/短缺物料调配/国产替代对照表)；④需求篇按客户产品列表**补全条目**，勿漏(如网络功放、智慧融合平台)；议程卡随之扩 2×3。找不到有价值信息才保留原样。

### B. 经营数据汇报型(business-data-report)
输入：业务数据+分析报告；目的：内部报告会。
固定(6)：封面←报告期+主题｜议程｜经营总览←KPI大数字卡(营收/毛利额/毛利率/新客/达成率)+同比环比｜问题诊断←Top问题+根因(长可拆页计弹性)｜行动目标←建议+下期目标｜Thanks。
弹性(6–18)：维度分析页，每页一维度：收入结构/盈利质量/客户(新老/大客/流失)/产品线/团队等；单维度量大可拆多页。
总页数12–24。
纪律：图表优先，数值页**禁纯文字**；结论先行；口径标注(同比/环比/时间窗/币种)；数据只出报告**禁杜撰**。
映射：①营收毛利→总览；②区域③产品线④客户⑤盈利质量→弹性页各1页；⑥问题→诊断；⑦行动→目标；封面/议程/Thanks照骨架。

### C. 行业知识培训型(industry-training)
输入：已确认行业报告；目的：内/外培训建认知。
固定(4)：封面←行业主题｜议程←模块卡(2×2/3×2)｜要点回顾←3–5记忆点+问答｜Thanks。
弹性(10–26)：M1行业概述(定义/分类/规模增速/阶段)→M2产业链(上下游/价值分布/关键环节)→M3技术产品趋势→M4竞争格局→M5需求应用→M6政策风险(含则用)；4–6模块×每模块2–5页。
总页数14–30。
纪律：递进(概念→结构→趋势→格局→应用)；模块小结助吸收；术语首现一句解释；数据标来源+年份；外训剔内部敏感。
映射：①定义规模→M1；②产业链→M2；③技术→M3；④竞争→M4；⑤需求→M5；⑥政策→M6；要点回顾←模块小结。

### D. 要求宣贯培训型(rules-briefing)
输入：制度/评分/操作文档；目的：宣贯。
固定(7)：封面｜议程(2×2卡)｜背景/为什么｜硬性要求/评分｜问题诊断←违规易错点｜行动清单←动作+时间表｜Thanks。
弹性(2–17)：条款详解1–12(少→总表；多→分组逐条)+正反案例1–4+考核/FAQ0–1。
总页数9–24。
纪律：条文与原文一致**禁改阈值**；案例服务理解；行动清单可执行。
映射：①背景→为什么；②总则+③评分→要求/评分+条款详解；④违规→诊断+案例；⑤时间表→行动清单。

### 兜底
未命中A–D：章节线性映射(每章1–2页)+询问确认；新类型按上式补表。

## 3. 视觉规范
### 3.1 自由设计配色(仅模版缺失或明确「自由设计」)
主`0D1B2A`/中蓝`1B3A5C`/青`00B4D8`/亮青`90E0EF`；警示`FF9F1C`/红`E63946`/绿`2A9D8F`；内容底`F5F8FB`/卡白`FFFFFF`。封面结尾深色，内容页浅色卡片。字体`Microsoft YaHei`。公司模版分支用§0品牌色，不混用。

### 3.2 视觉元素策略(全文统一)
「每页≥1视觉元素」为建议项非QA条件；公司模版自带装饰默认满足；未渲染验证注明；仅用户明确「严格遵循视觉规范」时升级强制并纳入QA。

## 4. Workflow
1. **读源材料**：search_files找报告/画像/数据读全文；必要时加载customer-profiling/business-data-analysis-methodology/industry-search。未命中→交互clarify追问「提供文件/路径，或按现有知识先出大纲待补？」；无交互→终止+头部标注「缺少源材料」。确认前禁拼凑。
2. **模版确认**(一次判定)：模版存在且未拒→company-ppt-template；缺失/损坏/拒绝→自由设计(§3.1)注明。
3. **识类型**：判§2哪类→取骨架；未命中走兜底。
4. **映射页结构**：按映射示例把源章节→骨架各页；每页一主题；定总页数+C。固定页无源数据→保留页写「未覆盖/待补充」禁杜撰。
5. **生成前自检**(未全勾禁进步骤7)：□材料通读□类型已定□骨架+页数已估□每页映射到源(无无源页)□C=总页数−2已算。
6. **计划摘要**(写脚本前必出；交互→确认，无交互→写入交付说明头部)：`类型:B｜总页数:14(固定6+弹性8)｜来源:经营分析报告2026H1.pdf｜页序:[封面,议程,经营总览,区域,产品线,客户,盈利质量,收入结构,团队,客群,行业,问题诊断,行动目标,Thanks]｜模版:company-ppt-template｜备注:总页数随内容弹性增减,此为一档示例`。
7. **写脚本**：先按§1.5为每页定版式。公司模版→python-pptx定制(helpers见§6.2，在模版副本追加shape)；简单文字页用线性h/p/gap；自由设计→pptxgenjs(16:9=10×5.625in)。勿硬塞纯文本。
8. **生成**：公司模版走§6.1(复制模版→填封面→新增C−1内容页→填标题正文)；自由设计python-pptx或pptxgenjs→exports/(npm全局EACCES→工作区`.pptx-tool`本地install)。
9. **结构化QA**：按§6.3跑边界(出血容差)+隐形框+关键词抽查；字体异常按§4.5。
10. **视觉QA(三态)**：soffice可用→PDF+pdftoppm目检；不可用→PIL色块预览。标注三选一：「已像素级渲染验证/仅结构化QA+布局预览/未经像素级验证」。
11. **修复循环**：对照§6.4标准；不达标→改→重生成→复跑QA；达标才停，修复后至少复跑一次。
12. **交付**：`MEDIA:/绝对路径/xxx.pptx`；默认本地不推企微。

## 4.5 异常矩阵（强制查询）
| 异常 | 步骤 | 动作 |
|---|---|---|
| 无源材料 | 1 | 交互clarify/非交互终止+标注 |
| 图形化后文字溢出 | 7/11 | 缩字号或扩卡/缩文案重排，重跑自检 |
| 固定页无源数据 | 4 | 保留页写「未覆盖/待补充」 |
| 含糊「自由设计」 | 2 | clarify确认「公司模版or自由设计」记录 |
| 突破上限+5页 | 4 | 暂停与用户确认 |
| 模版损坏 | 2 | 视缺失→自由设计+注明 |
| 字体不可用(broken file) | 9 | 按§6.3回退系统可用中文字体，禁忽略 |
| soffice不可用 | 10 | 仅布局预览，注明「未经像素级验证」 |

## 5. Pitfalls
**生成期**：
- 文本框必显式x/y/w/h：空options→7.5×0in隐形框(假溢出+隐形元素)
- header标题≤18–20等效中文字(24pt/宽8.7in≈≤24)；箭头链放正文
- 预留≥0.5in内边距；溢出/边界交§6.3
- 中文弯引号落盘→被规范化ASCII`"`截断→SyntaxError：**引号一律用「」直角引号，勿在脚本字符串用`"..."`**；写完`python -m py_compile`/`node --check`校验
- node颜色警告`"" is not a valid scheme color! "000000" used instead`=颜色undefined(数组越界)→静默转纯黑QA查不出；定位：python-pptx遍历shape找fill'000000'回查索引
- npm勿sudo，工作区本地装
- **演示/汇报型主视觉内容页禁线性h/p/gap平铺**(2026-09客户演示v1被否：文字框重叠/不图文/未图形化)——默认卡片化整页：圆角卡+编号徽标+色条+箭头/矩阵/结论条；坐标全显式
- **模版孤儿 slide 部件陷阱(2026-09冰恒物联踩坑)**：芯智控股模版的 `presentation.xml.rels` 含一个**孤儿 slide 关系**（`rId4→slide3.xml`，不在 sldIdLst；真正的 Thanks 结尾页是 `rId5→slide4.xml`）。`add_slide()` 的部件名用 `len(sldIdLst)+1` 计算，会与孤儿/Thanks 冲突，保存时产生**重复 `slideN.xml`**（zip 重复条目→文件损坏，PowerPoint 打不开或丢页）。**修复**：加载模版后先跑 `clean_template()`——①按 sldIdLst 引用集合删除孤儿 slide 关系(`rels.pop`)；②把被引用的 slide 部件连续重编号 `slide1..slideN`（改 `part._partname` + 失效 `target_ref/target_partname` 缓存）。重编号后 `add_slide` 部件名才连续正确。
- **`add_slide(layout='Logos')` 产出的是 3×3 图片占位符网格(logo 墙)，不是内容页**：模版真正的内容页(slide 1，含标题框+左上/右上 logo+蓝金页脚)是手工制作、`Logos` 版式自带的是 9 个 picture placeholder。新增内容页必须**复制 slide 1**（`copy.deepcopy` 非图片 shape + 对图片用 `add_picture(blob)` 重插，否则 `r:embed` 图片关系丢失→复制页 logo 损坏）。禁用 `add_slide('Logos')` 作为内容页。
- **封面背景是浅色渐变 `F0F7FE`（非深色），封面标题/副标题禁白色**(2026-09冰恒物联踩坑)：模版封面版式「标题和内容」的 layout 背景是 GRADIENT（起始 stop `F0F7FE` 近白），原始「替换标题名称」占位**继承深色主题色(无显式 color)**。若用 set_text_preserve 把封面标题/副标题强制设白→白字白底不可见。封面文字用**深蓝(如 `0B3D7A`/`143A63`/蓝灰 `4A6685`)**或深色系，勿沿用「深色区域→白字」的惯性判断。
- **python-pptx 的 `run.font.name` 只设 `a:latin` 不设 `a:ea`，CJK 文字显示方框(豆腐块)**(2026-09冰恒物联踩坑)：主题 fontScheme 的 `<a:ea typeface=""/>` 为空、拉丁为 `Lato`；缺 `a:ea` 时汉字回退 Lato(无中文字形)→方框，点击编辑态又显示正常(渲染路径不同)。**修复**：设 `r.font.name` 后必须同步设 `a:ea`（用 `_set_ea` helper，见§6.2），或改用「只改 `run.text` 保留原 rPr」的方式(勿 `tf.clear()` 重建 run)。**QA**：新增「全文 CJK run 是否缺 `a:ea`」检查（`rPr` 下无 `a:ea` 或无 typeface 即缺失）。
**QA期**：
- 跑前验字体可加载(broken file=损坏，存在≠可用)；优先思源黑体/Noto Sans CJK(§6.3)
- 每页用「期待关键词」抽查抓错位/缺失
- 渲染态按步骤10三态标注；视觉元素非QA条件(§3.2)
- 定制自检**逐页隔离**判重叠(qa_overlap整框bbox相交=候选，需人工复核剔除装饰/背景误报；勿跨页全局列表，否则假警报)；横排多卡矩阵总宽先验≤12.33in(4列品牌卡/4步流程卡曾排到12.78in越界0.09–0.15in，教训：总宽勿超内容可用宽)
**注册表/内容**：
- 口径：注册表页数=总页数(含封面/Thanks)；C=总页数−2；弹性禁凑页；高贴上限(+5确认)、低破下限
- A类含内部评级/金额字段落盘前剔除(泄露红线)
- 图表勿硬塞线性h/p/gap文字块：h/p只文字，图表python-pptx追加或嵌PNG
- 未命中注册表且未确认前，禁硬套A/B/C/D

## 6. 内联实现参考（自包含）

### 6.1 公司模版操作法（python-pptx）
```python
import shutil
from pptx import Presentation

TEMPLATE = '/data/hermes/skills/research/pptx-deck-generation/assets/芯智控股_PPT模版.pptx'

shutil.copy(TEMPLATE, out_path)   # 复制模版为输出(绝不在原件改)
prs = Presentation(out_path)
clean_template(prs)   # 必做：清除孤儿 slide 部件 + 连续重编号(见§5孤儿陷阱)，否则 add_slide 部件名冲突

def clean_template(prs):
    """删除未被 sldIdLst 引用的孤儿 slide 关系，并把被引用 slide 连续重编号 slide1..slideN。"""
    from pptx.opc.package import PackURI
    from pptx.opc.constants import RELATIONSHIP_TYPE as RT
    from pptx.oxml.ns import qn
    pres = prs.part
    sldIdLst = prs.slides._sldIdLst
    ordered_rids = [sld.get(qn('r:id')) for sld in sldIdLst]
    ref_set = set(ordered_rids)
    for rid in list(pres.rels.keys()):
        rel = pres.rels[rid]
        if rel.reltype == RT.SLIDE and rid not in ref_set:
            pres.rels.pop(rid)
    for i, rid in enumerate(ordered_rids, start=1):
        rel = pres.rels[rid]; part = rel.target_part
        new_pn = PackURI('/ppt/slides/slide%d.xml' % i)
        if str(part.partname) == str(new_pn): continue
        part._partname = new_pn
        for k in ('target_ref', 'target_partname'):
            if k in rel.__dict__: del rel.__dict__[k]

def layout_by_name(prs, name):    # 按版式名找layout，勿硬编码索引
    for i, l in enumerate(prs.slide_layouts):
        if l.name == name: return l
    raise KeyError(f'未找到版式: {name}')

def set_cover_title(prs, title):  # 封面替换占位「替换标题名称」
    for shape in prs.slides[0].shapes:
        if shape.has_text_frame and '替换标题名称' in shape.text_frame.text:
            for para in shape.text_frame.paragraphs:
                for run in para.runs:
                    run.text = title if '替换标题名称' in run.text else run.text
            return

def duplicate_content_slide(prs, src_index=1):  # 复制内容页(默认 slide 1)，共调C−1次(模板已有1个)
    import copy, tempfile, os
    from pptx.enum.shapes import MSO_SHAPE_TYPE
    src = prs.slides[src_index]
    dst = prs.slides.add_slide(src.slide_layout)
    for sh in list(dst.shapes):  # 移除 add_slide 自动创建的占位符
        sh._element.getparent().remove(sh._element)
    for sh in src.shapes:
        if sh.shape_type == MSO_SHAPE_TYPE.PICTURE:  # 图片必须重插，否则 r:embed 关系丢失
            blob = sh.image.blob; ext = sh.image.ext or 'png'
            fd, tmp = tempfile.mkstemp(suffix='.' + ext); os.write(fd, blob); os.close(fd)
            dst.shapes.add_picture(tmp, sh.left, sh.top, sh.width, sh.height); os.remove(tmp)
        else:
            dst.shapes._spTree.append(copy.deepcopy(sh._element))
    return dst  # 复用 run 替换把「PPT页面标题」→title
```
> 纪律：复制后操作副本；封面/结尾品牌页勿删；内容页目标总数=C(总页数−2)，模板已有1个→duplicate_content_slide共调C−1次，C−1<0则删多余；新增shape用§6.2 helpers+显式坐标；结尾页(2_Blank)若需置底，用 `prs.slides._sldIdLst` 重排（移出对应 sldId 再 append）。

### 6.2 卡片化版式 helpers（python-pptx，脚本顶部粘贴）
```python
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

BLUE=RGBColor(0x00,0x6C,0xB5); DEEP=RGBColor(0x00,0x62,0xA4); GOLD=RGBColor(0xFB,0xB1,0x30)
GREEN=RGBColor(0x27,0xB4,0x84); INK=RGBColor(0x1A,0x1A,0x1A); WHITE=RGBColor(0xFF,0xFF,0xFF)
LIGHT=RGBColor(0xF5,0xF8,0xFB)

def card(slide,x,y,w,h,fill=LIGHT,line=None):
    shp=slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE,Inches(x),Inches(y),Inches(w),Inches(h))
    shp.fill.solid(); shp.fill.fore_color.rgb=fill
    if line is None: shp.line.fill.background()
    else: shp.line.color.rgb=line; shp.line.width=Pt(1)
    return shp

def oval_badge(slide,x,y,d,num,fill=BLUE,size=14):
    shp=slide.shapes.add_shape(MSO_SHAPE.OVAL,Inches(x),Inches(y),Inches(d),Inches(d))
    shp.fill.solid(); shp.fill.fore_color.rgb=fill; shp.line.fill.background()
    tf=shp.text_frame; tf.clear(); p=tf.paragraphs[0]; p.alignment=PP_ALIGN.CENTER
    r=p.add_run(); r.text=str(num); r.font.size=Pt(size); r.font.bold=True; r.font.color.rgb=WHITE
    return shp

def arrow(slide,x,y,w,h,fill=GOLD):
    shp=slide.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW,Inches(x),Inches(y),Inches(w),Inches(h))
    shp.fill.solid(); shp.fill.fore_color.rgb=fill; shp.line.fill.background()
    return shp

def _set_ea(run, fontname):   # 东亚字体 a:ea（CJK 渲染必需；缺则汉字回退 Lato 显示方框，见§5）
    from pptx.oxml.ns import qn
    rPr = run._r.get_or_add_rPr()
    for ea in rPr.findall(qn('a:ea')): rPr.remove(ea)
    ea = rPr.makeelement(qn('a:ea'), {'typeface': fontname})
    latin = rPr.find(qn('a:latin'))
    if latin is not None: latin.addnext(ea)
    else: rPr.append(ea)

def normalize_fonts(prs, target='微软雅黑'):  # 全片字体统一：替换所有含「思源」的 a:latin/a:ea，覆盖模版自带文字
    from pptx.oxml.ns import qn
    def fix(r):
        rpr = r._r.get_or_add_rPr()
        for tag in ('a:latin', 'a:ea'):
            el = rpr.find(qn(tag))
            if el is not None and el.get('typeface') and '思源' in el.get('typeface'):
                el.set('typeface', target)
    for slide in prs.slides:
        def walk(shapes):
            for sh in shapes:
                if sh.shape_type == 6:  # GROUP 递归
                    walk(sh.shapes); continue
                if sh.has_text_frame:
                    for para in sh.text_frame.paragraphs:
                        for r in para.runs: fix(r)
        walk(slide.shapes)

def T(slide,x,y,w,h,text,size=14,bold=False,color=INK,align=PP_ALIGN.LEFT,font='微软雅黑',anchor=MSO_ANCHOR.TOP):
    tb=slide.shapes.add_textbox(Inches(x),Inches(y),Inches(w),Inches(h))
    tf=tb.text_frame; tf.word_wrap=True; tf.clear(); tf.vertical_anchor=anchor
    lines=text.split('\n') if isinstance(text,str) else text
    for i,line in enumerate(lines):
        p=tf.paragraphs[0] if i==0 else tf.add_paragraph()
        p.alignment=align; r=p.add_run(); r.text=line
        r.font.size=Pt(size); r.font.bold=bold; r.font.color.rgb=color
        r.font.name=font; _set_ea(r, font)   # 同步东亚字体，防 CJK 方框
    return tb

def sec_header(slide,x,y,text,num=None,size=20,color=DEEP):
    if num is not None:
        oval_badge(slide,x,y-0.05,0.35,num,fill=BLUE); x+=0.45
    return T(slide,x,y,8.5,0.4,text,size=size,bold=True,color=color)
```
> 选型对照§1.5：流程=node卡+arrow；对比=蓝/金双卡；结论=全宽DEEP底白字；KPI=大数字卡(60–72pt+小标签)。
> **标题约定(用户定，2026-09)**：封面主标题**居中**；**子页面(内容页)标题一律左对齐 + 深蓝 `0B3D7A`(NAVY，与封面同色)**——居中会让不同长度标题的起始 x 不固定。子页标题用 `set_text_preserve(..., align=PP_ALIGN.LEFT, color=NAVY)`，勿用默认居中。

### 6.3 结构化 QA 逻辑（python-pptx + PIL，脚本末尾跑）
```python
from pptx import Presentation
from pptx.util import Emu
from PIL import ImageFont

def qa_bounds(prs, bleed=0.05):  # 边界检测，出血容差0.05in=457200EMU
    issues=[]; b=Emu(int(bleed*914400)); W,H=prs.slide_width,prs.slide_height
    for si,slide in enumerate(prs.slides):
        for shp in slide.shapes:
            if shp.left is None: continue
            if shp.left<-b or shp.top<-b or shp.left+shp.width>W+b or shp.top+shp.height>H+b:
                issues.append((si,shp.name,'越界'))
    return issues

def qa_invisible_textboxes(prs):  # 空options→w≈7.5in×h≈0隐形框
    out=[]
    for si,slide in enumerate(prs.slides):
        for shp in slide.shapes:
            if shp.has_text_frame and shp.width and shp.height:
                if shp.width==Emu(6858000) and shp.height==Emu(0):
                    out.append((si,shp.name))
    return out

def qa_keywords(prs,page_keys):  # 每页期待关键词抽查(any命中即过)
    missing=[]
    for si,keys in page_keys.items():
        text=' '.join(sh.text_frame.text for sh in prs.slides[si].shapes if sh.has_text_frame)
        if not any(k in text for k in keys): missing.append(si)
    return missing

def find_cjk_font():  # 字体可加载检测(broken file=损坏，存在≠可用)
    for path in ['/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
                 '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc',
                 '/usr/share/fonts/truetype/arphic/uming.ttc']:
        try: ImageFont.truetype(path,20); return path
        except Exception: continue
    return None  # 找不到→默认字体，注明「字体未显式指定」

def qa_overlap(prs):  # 逐页隔离重叠自检：整框bbox相交=候选，需人工复核(装饰/背景色块相交非真实文字重叠)
    out=[]
    for si,slide in enumerate(prs.slides):
        boxes=[(sh.name,sh.left,sh.top,sh.left+sh.width,sh.top+sh.height)
               for sh in slide.shapes if sh.left is not None]
        for a in range(len(boxes)):
            for b2 in range(a+1,len(boxes)):
                na,x1,y1,x2,y2=boxes[a]; nb,u1,v1,u2,v2=boxes[b2]
                if x1<u2 and u1<x2 and y1<v2 and v1<y2: out.append((si,na,nb))
    return out

def qa_ea_font(prs):  # CJK 方框预防：返回每个含汉字却缺 a:ea 的 run（rPr 下无 a:ea 或无 typeface）
    A='{http://schemas.openxmlformats.org/drawingml/2006/main}'
    missing=[]
    for si,slide in enumerate(prs.slides):
        def walk(shapes):
            for sh in shapes:
                if sh.shape_type==6: walk(sh.shapes); continue
                if sh.has_text_frame:
                    for para in sh.text_frame.paragraphs:
                        for r in para.runs:
                            if r.text and any('\u4e00'<=c<='\u9fff' for c in r.text):
                                rPr=r._r.find(A+'rPr'); ea=rPr.find(A+'ea') if rPr is not None else None
                                if ea is None or not ea.get('typeface'): missing.append((si,r.text[:15]))
        walk(slide.shapes)
    return missing  # 为空=全部已设 a:ea ✓
```

### 6.4 QA 通过标准（停止修复循环的充要条件）
①无越界(出血0.05in) ②无隐形框(0个7.5×0in) ③关键词抽查缺失页占比≤10%(页级口径：≥90%的页至少命中1个期待关键词) ④字体可加载 ⑤实际页数与步骤6摘要一致(C口径)。

**坐标预算(python-pptx口径，公司模版16:9=13.333×7.5in)**：左右边距≥0.5in→可用宽≤12.33in；横排多卡矩阵总宽先验≤12.33in(含间距)；正文区y≈1.3–7.2(高≈5.9in)；卡文字≤2行/块；标题≤18–20等效中文字。**自由设计pptxgenjs画布10×5.625in，坐标×0.75换算。**
