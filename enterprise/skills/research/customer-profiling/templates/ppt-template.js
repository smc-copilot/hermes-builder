/**
 * Customer Profiling PPT Template — Midnight Executive
 * 
 * Usage: Copy this file and replace all {{PLACEHOLDER}} sections with
 * company-specific data from the completed Markdown profiling report.
 * 
 * Dependencies: pptxgenjs, react-icons, react, react-dom, sharp
 * Install: npm install pptxgenjs react-icons react react-dom sharp
 * 
 * To use from a skill context, load via:
 *   skill_view(name="customer-profiling", file_path="templates/ppt-template.js")
 */

const pptxgen = require("pptxgenjs");
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const {
  FaBuilding, FaMicrochip, FaChartBar, FaShieldAlt,
  FaRocket, FaBullseye, FaUserTie, FaHandshake,
  FaExclamationTriangle, FaTv, FaWifi, FaCar,
  FaServer, FaGlobeAsia, FaIndustry, FaMoneyBillWave,
  FaStar, FaCheckCircle, FaArrowRight, FaPhone, FaHeadset
} = require("react-icons/fa");

// ============================================================
// Color Palette: Midnight Executive
// ============================================================
const C = {
  navy: "1E2761", navyDark: "151D4A", iceBlue: "CADCFC",
  gold: "F0B429", lightBg: "F5F7FA", white: "FFFFFF",
  tableHeader: "1E2761", tableStripe: "EBF0FA",
  textDark: "1A1A2E", textMuted: "6B7280",
  accentGreen: "10B981", accentRed: "EF4444", accentOrange: "F59E0B",
  cardBorder: "E5E7EB", progressBg: "E5E7EB",
  progressFill1: "1E2761", progressFill2: "3B82F6", progressFill3: "8B5CF6",
};

// ============================================================
// Icon helpers
// ============================================================
function renderIconSvg(IconComponent, color = "#000000", size = 256) {
  return ReactDOMServer.renderToStaticMarkup(
    React.createElement(IconComponent, { color, size: String(size) })
  );
}
async function iconToBase64Png(IconComponent, color, size = 256) {
  const svg = renderIconSvg(IconComponent, color, size);
  const buf = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + buf.toString("base64");
}

// IMPORTANT: PptxGenJS mutates option objects in-place. Always use a factory.
const makeShadow = () => ({
  type: "outer", blur: 6, offset: 2, angle: 135, color: "000000", opacity: 0.12,
});

// ============================================================
// Slide-building helpers
// ============================================================

function addTopBarCard(slide, x, y, w, h, barColor) {
  slide.addShape("rect", { x, y, w, h, fill: { color: C.white }, shadow: makeShadow() });
  slide.addShape("rect", { x, y, w, h: 0.06, fill: { color: barColor } });
}

function addCircleNumber(slide, x, y, num, color = C.navy) {
  const r = 0.22;
  slide.addShape("oval", { x, y, w: r * 2, h: r * 2, fill: { color } });
  slide.addText(String(num), {
    x, y, w: r * 2, h: r * 2, fontSize: 14, fontFace: "Arial",
    color: C.white, bold: true, align: "center", valign: "middle", margin: 0,
  });
}

function addProgressBar(slide, x, y, w, h, pct, color) {
  slide.addShape("rect", { x, y, w, h, fill: { color: C.progressBg }, rectRadius: h / 2 });
  slide.addShape("rect", { x, y, w: w * Math.min(pct / 100, 1), h, fill: { color }, rectRadius: h / 2 });
}

function addSectionTitle(slide, title, iconData) {
  if (iconData) {
    slide.addImage({ data: iconData, x: 0.5, y: 0.35, w: 0.38, h: 0.38 });
    slide.addText(title, { x: 1.0, y: 0.3, w: 8.5, h: 0.55, fontSize: 26, fontFace: "Arial", color: C.navy, bold: true, margin: 0 });
  } else {
    slide.addText(title, { x: 0.5, y: 0.3, w: 9, h: 0.55, fontSize: 26, fontFace: "Arial", color: C.navy, bold: true, margin: 0 });
  }
  slide.addShape("rect", { x: 0.5, y: 0.95, w: 1.2, h: 0.04, fill: { color: C.gold } });
}

// ============================================================
// MAIN
// ============================================================
async function main() {
  const pres = new pptxgen();
  pres.layout = "LAYOUT_16x9";
  pres.author = "Hermes Researcher";

  // ═══════════════════════════════════════════════════════
  // DATA SECTION — replace all {{...}} with company data
  // ═══════════════════════════════════════════════════════
  const COMPANY = {
    fullName: "{{公司全称}}",
    shortName: "{{公司简称}}",
    stockCode: "{{股票代码，无则填''}}",
    englishName: "{{英文名称}}",
    registeredCapital: "{{注册资本}}",
    founded: "{{成立时间}}",
    legalRep: "{{法定代表人}}",
    parent: "{{母公司/集团}}",
    address: "{{注册地址}}",
    factory: "{{制造基地}}",
    employees: "{{员工规模}}",
    industry: "{{行业定位}}",
    coverBadges: [
      { text: "{{标签1}}", color: "F0B429" },
      { text: "{{标签2}}", color: "CADCFC" },
      { text: "{{标签3}}", color: "CADCFC" },
    ],
    warningText: "{{盈利预警，无则填null}}",
  };

  const KPI_CARDS = [
    { iconName: "money", value: "{{KPI1}}", label: "{{KPI1标签}}", color: C.navy },
    { iconName: "microchip", value: "{{KPI2}}", label: "{{KPI2标签}}", color: "#3B82F6" },
    { iconName: "globe", value: "{{KPI3}}", label: "{{KPI3标签}}", color: "#8B5CF6" },
    { iconName: "warning", value: "{{KPI4}}", label: "{{KPI4标签}}", color: C.accentOrange },
  ];

  const INFO_TABLE = [
    ["公司全称", COMPANY.fullName], ["成立时间", COMPANY.founded],
    ["注册资本", COMPANY.registeredCapital], ["法定代表人", COMPANY.legalRep],
    ["上市主体", COMPANY.stockCode ? `${COMPANY.shortName} (${COMPANY.stockCode})` : "非上市"],
    ["母公司", COMPANY.parent], ["注册地址", COMPANY.address],
    ["制造基地", COMPANY.factory], ["员工规模", COMPANY.employees],
    ["行业定位", COMPANY.industry],
  ];

  const PRODUCTS = [
    { iconName: "tv", barColor: C.navy, title: "{{P1名称}}", subtitle: "{{P1英文}}",
      items: ["{{P1-1}}","{{P1-2}}","{{P1-3}}","{{P1-4}}","{{P1-5}}"], revenuePct: "{{P1占比}}" },
    { iconName: "wifi", barColor: "#3B82F6", title: "{{P2名称}}", subtitle: "{{P2英文}}",
      items: ["{{P2-1}}","{{P2-2}}","{{P2-3}}","{{P2-4}}","{{P2-5}}"], revenuePct: "{{P2占比}}" },
    { iconName: "tv", barColor: "#8B5CF6", title: "{{P3名称}}", subtitle: "{{P3英文}}",
      items: ["{{P3-1}}","{{P3-2}}","{{P3-3}}","{{P3-4}}"], revenuePct: "{{P3占比}}" },
    { iconName: "server", barColor: C.accentOrange, title: "{{P4名称}}", subtitle: "{{P4英文}}",
      items: ["{{P4-1}}","{{P4-2}}","{{P4-3}}","{{P4-4}}"], revenuePct: "{{P4占比}}" },
  ];

  const CORE_CHIPS = [
    { id:1, cat:"{{芯1}}", logic:"{{逻1}}", products:"{{产1}}", brand:"{{牌1}}", barColor:C.navy },
    { id:2, cat:"{{芯2}}", logic:"{{逻2}}", products:"{{产2}}", brand:"{{牌2}}", barColor:"#3B82F6" },
    { id:3, cat:"{{芯3}}", logic:"{{逻3}}", products:"{{产3}}", brand:"{{牌3}}", barColor:"#8B5CF6" },
    { id:4, cat:"{{芯4}}", logic:"{{逻4}}", products:"{{产4}}", brand:"{{牌4}}", barColor:C.accentOrange },
    { id:5, cat:"{{芯5}}", logic:"{{逻5}}", products:"{{产5}}", brand:"{{牌5}}", barColor:"#10B981" },
    { id:6, cat:"{{芯6}}", logic:"{{逻6}}", products:"{{产6}}", brand:"{{牌6}}", barColor:"#EF4444" },
    { id:7, cat:"{{芯7}}", logic:"{{逻7}}", products:"{{产7}}", brand:"{{牌7}}", barColor:"#6366F1" },
  ];

  const BRANDS = [
    { name:"{{B1}}", cat:"{{B1C}}", highlight:true, color:C.navy },
    { name:"{{B2}}", cat:"{{B2C}}", highlight:true, color:C.navy },
    { name:"{{B3}}", cat:"{{B3C}}", highlight:true, color:C.navy },
    { name:"{{B4}}", cat:"{{B4C}}", highlight:false, color:"#3B82F6" },
    { name:"{{B5}}", cat:"{{B5C}}", highlight:false, color:"#3B82F6" },
    { name:"{{B6}}", cat:"{{B6C}}", highlight:true, color:"#8B5CF6" },
    { name:"{{B7}}", cat:"{{B7C}}", highlight:false, color:"#8B5CF6" },
    { name:"{{B8}}", cat:"{{B8C}}", highlight:false, color:C.accentOrange },
    { name:"{{B9}}", cat:"{{B9C}}", highlight:true, color:"#10B981" },
    { name:"{{B10}}", cat:"{{B10C}}", highlight:true, color:"#EF4444" },
  ];

  const EXTENDED_CHIPS = [
    ["1","{{E1}}","{{EL1}}","{{EP1}}","{{EB1}}"],
    ["2","{{E2}}","{{EL2}}","{{EP2}}","{{EB2}}"],
    ["3","{{E3}}","{{EL3}}","{{EP3}}","{{EB3}}"],
    ["4","{{E4}}","{{EL4}}","{{EP4}}","{{EB4}}"],
    ["5","{{E5}}","{{EL5}}","{{EP5}}","{{EB5}}"],
    ["6","{{E6}}","{{EL6}}","{{EP6}}","{{EB6}}"],
    ["7","{{E7}}","{{EL7}}","{{EP7}}","{{EB7}}"],
  ];

  const SCORING = {
    totalScore: {{总分}}, gradeLabel: "{{评级标签}}", gradeColor: "F59E0B",
    dims: [
      { label:"公司基本面", sub:"{{D1说明}}", pct:{{D1%}}, color:C.progressFill1, score:"{{D1分}}" },
      { label:"业务匹配度", sub:"{{D2说明}}", pct:{{D2%}}, color:C.progressFill2, score:"{{D2分}}" },
      { label:"发展潜力", sub:"{{D3说明}}", pct:{{D3%}}, color:C.progressFill3, score:"{{D3分}}" },
    ],
    extraBonus: "{{加分说明}}",
  };

  const COMPETITIVE_TABLE = [
    ["正品保障","✅","✅","✅","✅ {{我方}}"],
    ["短缺物料调配","{{竞A}}","{{竞B}}","{{竞C}}","✅ {{我方}}"],
    ["FAE 深度","{{竞A}}","{{竞B}}","{{竞C}}","✅ {{我方}}"],
    ["大陆本地响应","{{竞A}}","{{竞B}}","{{竞C}}","✅ {{我方}}"],
    ["EOL 预警管理","{{竞A}}","{{竞B}}","{{竞C}}","✅ {{我方}}"],
    ["出口管制合规","{{竞A}}","{{竞B}}","{{竞C}}","✅ {{我方}}"],
    ["国产化替代方案","{{竞A}}","{{竞B}}","{{竞C}}","✅ {{我方}}"],
  ];

  const STRATEGY = { position:"{{策略定位}}", detail:"{{策略描述}}" };

  const ACTION_STEPS = [
    { num:"01", title:"{{S1T}}", color:C.navy, items:["{{S1-1}}","{{S1-2}}","{{S1-3}}"] },
    { num:"02", title:"{{S2T}}", color:"#3B82F6", items:["{{S2-1}}","{{S2-2}}","{{S2-3}}"] },
    { num:"03", title:"{{S3T}}", color:"#8B5CF6", items:["{{S3-1}}","{{S3-2}}","{{S3-3}}"] },
  ];

  const CONTACTS = [
    { priority:"P0", target:"{{P0}}", method:"{{P0M}}", reason:"{{P0R}}" },
    { priority:"P1", target:"{{P1}}", method:"{{P1M}}", reason:"{{P1R}}" },
    { priority:"P2", target:"{{P2}}", method:"{{P2M}}", reason:"{{P2R}}" },
  ];

  const SUMMARY = [
    { title:"客户定位", content:"{{客户定位}}" },
    { title:"芯片需求规模", content:"{{需求规模}}" },
    { title:"切入可行性", content:"{{可行性}}" },
  ];

  const RISKS = ["{{风险1}}","{{风险2}}","{{风险3}}","{{风险4}}"];

  // ═══════════════ END DATA ═══════════════

  pres.title = `${COMPANY.fullName} 客户画像报告`;

  const ICON_MAP = { building:FaBuilding, microchip:FaMicrochip, chart:FaChartBar, shield:FaShieldAlt, rocket:FaRocket, bullseye:FaBullseye, userTie:FaUserTie, handshake:FaHandshake, warning:FaExclamationTriangle, tv:FaTv, wifi:FaWifi, car:FaCar, server:FaServer, globe:FaGlobeAsia, industry:FaIndustry, money:FaMoneyBillWave, star:FaStar, check:FaCheckCircle, arrow:FaArrowRight, headset:FaHeadset, phone:FaPhone };
  const icons = {};
  for (const [n, Cmp] of Object.entries(ICON_MAP)) { icons[n]=await iconToBase64Png(Cmp,"#FFFFFF",256); icons[n+"Navy"]=await iconToBase64Png(Cmp,"#1E2761",256); }
  icons.bullseyeGold=await iconToBase64Png(FaBullseye,"#F0B429",256);

  // === SLIDE 1: COVER ===
  { const s=pres.addSlide(); s.background={color:C.navyDark};
    s.addShape("rect",{x:0,y:0,w:10,h:0.08,fill:{color:C.gold}});
    s.addText(COMPANY.fullName,{x:0.8,y:1.6,w:8.4,h:1.0,fontSize:40,fontFace:"Arial",color:C.white,bold:true,margin:0});
    s.addText(COMPANY.englishName,{x:0.8,y:2.5,w:8.4,h:0.5,fontSize:14,fontFace:"Calibri",color:C.iceBlue,margin:0,charSpacing:3});
    s.addShape("rect",{x:0.8,y:3.15,w:2.5,h:0.04,fill:{color:C.gold}});
    COMPANY.coverBadges.forEach((b,i)=>{const bx=0.8+i*2.7; s.addShape("rect",{x:bx,y:3.4,w:2.4,h:0.42,fill:{color:b.color,transparency:85},rectRadius:0.05}); s.addText(b.text,{x:bx,y:3.4,w:2.4,h:0.42,fontSize:11,fontFace:"Calibri",color:C.white,align:"center",valign:"middle",margin:0});});
    s.addText("客户画像报告",{x:0.8,y:4.2,w:5,h:0.5,fontSize:18,fontFace:"Calibri",color:C.iceBlue,margin:0});
    const td=new Date().toISOString().slice(0,10); s.addText(`${td}  |  Confidential`,{x:7.5,y:5.05,w:2.2,h:0.35,fontSize:10,fontFace:"Calibri",color:C.textMuted,align:"right",margin:0});
  }

  // === SLIDE 2: OVERVIEW ===
  { const s=pres.addSlide(); s.background={color:C.lightBg}; addSectionTitle(s,"公司概览",icons.buildingNavy);
    const h=[{text:"项目",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:11,fontFace:"Arial"}},{text:"内容",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:11,fontFace:"Arial"}}];
    s.addTable([h,...INFO_TABLE],{x:0.5,y:1.2,w:5.2,border:{pt:0.5,color:C.cardBorder},colW:[1.6,3.6],rowH:Array(INFO_TABLE.length+1).fill(0.32),fontFace:"Calibri",fontSize:10,color:C.textDark,autoPage:false});
    KPI_CARDS.forEach((c,i)=>{const cx=6.0,cy=1.2+i*1.05; addTopBarCard(s,cx,cy,3.5,0.92,c.color); if(icons[c.iconName]) s.addImage({data:icons[c.iconName],x:cx+0.15,y:cy+0.18,w:0.35,h:0.35}); s.addText(c.value,{x:cx+0.6,y:cy+0.14,w:2.7,h:0.4,fontSize:22,fontFace:"Arial",color:c.color,bold:true,margin:0}); s.addText(c.label,{x:cx+0.6,y:cy+0.52,w:2.7,h:0.3,fontSize:10,fontFace:"Calibri",color:C.textMuted,margin:0});});
    if(COMPANY.warningText){s.addShape("rect",{x:0.5,y:4.7,w:9.0,h:0.6,fill:{color:"#FEF3C7"},rectRadius:0.04}); s.addText(COMPANY.warningText,{x:0.7,y:4.72,w:8.6,h:0.55,fontFace:"Calibri",fontSize:11,color:"#92400E",valign:"middle",margin:0});}
  }

  // === SLIDE 3: PRODUCTS ===
  { const s=pres.addSlide(); s.background={color:C.lightBg}; addSectionTitle(s,"核心产品矩阵",icons.microchipNavy);
    PRODUCTS.forEach((p,i)=>{const col=i%2,row=Math.floor(i/2),cx=0.5+col*4.6,cy=1.2+row*2.1; addTopBarCard(s,cx,cy,4.2,1.95,p.barColor); const id=icons[p.iconName+"Navy"]||icons[p.iconName]; if(id){s.addShape("oval",{x:cx+0.15,y:cy+0.15,w:0.46,h:0.46,fill:{color:p.barColor,transparency:15}}); s.addImage({data:id,x:cx+0.2,y:cy+0.2,w:0.36,h:0.36});} s.addText(p.title,{x:cx+0.72,y:cy+0.12,w:2.2,h:0.35,fontSize:16,fontFace:"Arial",color:C.textDark,bold:true,margin:0}); s.addText(p.subtitle,{x:cx+0.72,y:cy+0.42,w:2.2,h:0.25,fontSize:9,fontFace:"Calibri",color:C.textMuted,margin:0}); s.addShape("rect",{x:cx+3.35,y:cy+0.15,w:0.7,h:0.35,fill:{color:p.barColor,transparency:80},rectRadius:0.04}); s.addText(p.revenuePct,{x:cx+3.35,y:cy+0.15,w:0.7,h:0.35,fontSize:13,fontFace:"Arial",color:p.barColor,bold:true,align:"center",valign:"middle",margin:0}); p.items.forEach((it,j)=>{s.addShape("oval",{x:cx+0.2,y:cy+0.8+j*0.24,w:0.08,h:0.08,fill:{color:p.barColor}}); s.addText(it,{x:cx+0.38,y:cy+0.72+j*0.24,w:3.5,h:0.24,fontSize:10,fontFace:"Calibri",color:C.textDark,margin:0});});});
  }

  // === SLIDE 4: CORE CHIPS ===
  { const s=pres.addSlide(); s.background={color:C.lightBg}; addSectionTitle(s,"芯片需求 — 核心推荐清单 (★★★)",icons.chartNavy);
    CORE_CHIPS.forEach((c,i)=>{const cy=1.2+i*0.58; addCircleNumber(s,0.5,cy+0.08,c.id,c.barColor); s.addText(c.cat,{x:1.05,y:cy+0.02,w:2.8,h:0.28,fontSize:12,fontFace:"Arial",color:C.textDark,bold:true,margin:0}); s.addText(c.logic,{x:1.05,y:cy+0.28,w:2.8,h:0.22,fontSize:9,fontFace:"Calibri",color:C.textMuted,margin:0}); s.addText(c.products,{x:4.0,y:cy+0.05,w:2.2,h:0.45,fontSize:10,fontFace:"Calibri",color:C.textDark,valign:"middle",margin:0}); c.brand.split(" / ").forEach((b,j)=>{const bx=6.4+j*1.2; s.addShape("rect",{x:bx,y:cy+0.1,w:1.05,h:0.32,fill:{color:C.navy,transparency:90},rectRadius:0.03}); s.addText(b,{x:bx,y:cy+0.1,w:1.05,h:0.32,fontSize:8,fontFace:"Calibri",color:C.navy,bold:true,align:"center",valign:"middle",margin:0});});});
  }

  // === SLIDE 5: BRANDS ===
  { const s=pres.addSlide(); s.background={color:C.lightBg}; addSectionTitle(s,"授权品牌匹配亮点",icons.handshake);
    BRANDS.forEach((b,i)=>{const col=i%5,row=Math.floor(i/5),bx=0.5+col*1.85,by=1.2+row*2.05; addTopBarCard(s,bx,by,1.7,1.85,b.color); if(b.highlight)s.addImage({data:icons.star,x:bx+1.3,y:by+0.1,w:0.22,h:0.22}); s.addText(b.name,{x:bx+0.1,y:by+0.2,w:1.5,h:0.35,fontSize:12,fontFace:"Arial",color:C.textDark,bold:true,margin:0}); s.addText(b.cat,{x:bx+0.1,y:by+0.55,w:1.5,h:0.25,fontSize:9,fontFace:"Calibri",color:C.textMuted,margin:0}); s.addImage({data:icons.check,x:bx+0.1,y:by+1.3,w:0.22,h:0.22}); s.addText("授权代理",{x:bx+0.38,y:by+1.3,w:1.2,h:0.22,fontSize:9,fontFace:"Calibri",color:C.accentGreen,bold:true,margin:0});});
  }

  // === SLIDE 6: EXTENDED ===
  { const s=pres.addSlide(); s.background={color:C.lightBg}; addSectionTitle(s,"扩展机会清单 (★★☆)",icons.rocketNavy);
    const h=[{text:"序号",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:10,fontFace:"Arial",align:"center"}},{text:"芯片品类",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:10,fontFace:"Arial"}},{text:"匹配逻辑",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:10,fontFace:"Arial"}},{text:"匹配产品",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:10,fontFace:"Arial"}},{text:"推荐品牌",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:10,fontFace:"Arial"}}];
    s.addTable([h,...EXTENDED_CHIPS],{x:0.5,y:1.2,w:9.0,border:{pt:0.5,color:C.cardBorder},colW:[0.5,1.8,2.0,1.7,3.0],rowH:[0.4,...Array(EXTENDED_CHIPS.length).fill(0.45)],fontFace:"Calibri",fontSize:10,color:C.textDark,autoPage:false});
    s.addShape("rect",{x:0.5,y:4.8,w:9.0,h:0.5,fill:{color:"#EFF6FF"},rectRadius:0.04}); s.addText("💡 以上品类视客户具体产品型号配置而定，首单可从交期压力较大或已有替代需求的品类切入。",{x:0.7,y:4.82,w:8.6,h:0.45,fontSize:10,fontFace:"Calibri",color:"#1E40AF",valign:"middle",margin:0});
  }

  // === SLIDE 7: SCORING ===
  { const s=pres.addSlide(); s.background={color:C.lightBg}; addSectionTitle(s,"客户量化评分",icons.chartNavy);
    s.addShape("rect",{x:0.5,y:1.3,w:3.8,h:3.8,fill:{color:C.white},shadow:makeShadow()}); s.addText(String(SCORING.totalScore),{x:0.5,y:1.8,w:3.8,h:1.2,fontSize:72,fontFace:"Arial",color:C.navy,bold:true,align:"center",valign:"middle",margin:0}); s.addText("/ 100 分",{x:0.5,y:2.85,w:3.8,h:0.4,fontSize:18,fontFace:"Calibri",color:C.textMuted,align:"center",margin:0}); s.addShape("rect",{x:1.3,y:3.35,w:2.2,h:0.5,fill:{color:SCORING.gradeColor,transparency:15},rectRadius:0.25}); s.addText(SCORING.gradeLabel,{x:1.3,y:3.35,w:2.2,h:0.5,fontSize:14,fontFace:"Arial",color:SCORING.gradeColor,bold:true,align:"center",valign:"middle",margin:0});
    SCORING.dims.forEach((d,i)=>{const dy=1.3+i*1.2; s.addText(d.label,{x:4.7,y:dy,w:2.0,h:0.3,fontSize:14,fontFace:"Arial",color:C.textDark,bold:true,margin:0}); s.addText(d.sub,{x:4.7,y:dy+0.28,w:2.8,h:0.22,fontSize:9,fontFace:"Calibri",color:C.textMuted,margin:0}); s.addText(d.score,{x:8.7,y:dy+0.05,w:0.8,h:0.3,fontSize:16,fontFace:"Arial",color:d.color,bold:true,align:"right",margin:0}); addProgressBar(s,4.7,dy+0.58,4.8,0.16,d.pct,d.color);});
    s.addShape("rect",{x:4.7,y:4.65,w:4.8,h:0.7,fill:{color:"#FEF3C7"},rectRadius:0.04}); s.addText(SCORING.extraBonus,{x:4.9,y:4.68,w:4.4,h:0.62,fontFace:"Calibri",fontSize:10,color:"#92400E",valign:"middle",margin:0});
  }

  // === SLIDE 8: COMPETITIVE ===
  { const s=pres.addSlide(); s.background={color:C.lightBg}; addSectionTitle(s,"竞品格局与差异化优势",icons.bullseyeGold);
    const h=[{text:"能力维度",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:10,fontFace:"Arial"}},{text:"全球分销商\n(Arrow/Avnet)",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:9,fontFace:"Arial",align:"center"}},{text:"台资分销\n(大联大/文晔)",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:9,fontFace:"Arial",align:"center"}},{text:"原厂直采\n(博通/Realtek)",options:{fill:{color:C.navy},color:C.white,bold:true,fontSize:9,fontFace:"Arial",align:"center"}},{text:"★ 我方优势",options:{fill:{color:C.accentGreen},color:C.white,bold:true,fontSize:10,fontFace:"Arial",align:"center"}}];
    s.addTable([h,...COMPETITIVE_TABLE],{x:0.5,y:1.2,w:9.0,border:{pt:0.5,color:C.cardBorder},colW:[2.0,1.7,1.7,1.7,1.9],rowH:[0.55,...Array(COMPETITIVE_TABLE.length).fill(0.42)],fontFace:"Calibri",fontSize:9,color:C.textDark,autoPage:false});
    s.addShape("rect",{x:0.5,y:4.45,w:9.0,h:0.85,fill:{color:C.white},shadow:makeShadow()}); s.addText([{text:"🎯 切入策略定位：",options:{bold:true,fontSize:12,color:C.navy}},{text:STRATEGY.position,options:{bold:true,fontSize:12,color:C.gold}},{text:` — ${STRATEGY.detail}`,options:{fontSize:10,color:C.textDark}}],{x:0.7,y:4.5,w:8.6,h:0.75,fontFace:"Calibri",valign:"middle",margin:0});
  }

  // === SLIDE 9: ACTION PLAN ===
  { const s=pres.addSlide(); s.background={color:C.lightBg}; addSectionTitle(s,"切入策略与行动建议",icons.rocketNavy);
    ACTION_STEPS.forEach((st,i)=>{const sx=0.5+i*3.1,sy=1.2; addTopBarCard(s,sx,sy,2.85,2.5,st.color); s.addText(st.num,{x:sx+0.15,y:sy+0.15,w:0.55,h:0.55,fontSize:24,fontFace:"Arial",color:st.color,bold:true,valign:"middle",margin:0}); s.addText(st.title,{x:sx+0.7,y:sy+0.2,w:2.0,h:0.4,fontSize:15,fontFace:"Arial",color:C.textDark,bold:true,margin:0}); st.items.forEach((it,j)=>{s.addShape("oval",{x:sx+0.2,y:sy+0.9+j*0.42,w:0.08,h:0.08,fill:{color:st.color}}); s.addText(it,{x:sx+0.4,y:sy+0.82+j*0.42,w:2.3,h:0.4,fontSize:9,fontFace:"Calibri",color:C.textDark,valign:"middle",margin:0});});});
    s.addShape("rect",{x:0.5,y:4.0,w:9.0,h:1.35,fill:{color:C.white},shadow:makeShadow()}); s.addText("🎯 优先接触策略",{x:0.7,y:4.05,w:4.0,h:0.35,fontSize:14,fontFace:"Arial",color:C.navy,bold:true,margin:0}); const pc={P0:C.accentRed,P1:C.accentOrange,P2:"#3B82F6"};
    CONTACTS.forEach((ct,i)=>{const cy=4.45+i*0.27,pc_=pc[ct.priority]||C.navy; s.addShape("rect",{x:0.7,y:cy,w:0.35,h:0.22,fill:{color:pc_},rectRadius:0.03}); s.addText(ct.priority,{x:0.7,y:cy,w:0.35,h:0.22,fontSize:8,fontFace:"Arial",color:C.white,bold:true,align:"center",valign:"middle",margin:0}); s.addText(ct.target,{x:1.15,y:cy,w:3.0,h:0.22,fontSize:9,fontFace:"Calibri",color:C.textDark,valign:"middle",margin:0}); s.addText(ct.method,{x:4.2,y:cy,w:2.5,h:0.22,fontSize:9,fontFace:"Calibri",color:C.textMuted,valign:"middle",margin:0}); s.addText(ct.reason,{x:6.7,y:cy,w:2.5,h:0.22,fontSize:9,fontFace:"Calibri",color:C.textMuted,valign:"middle",margin:0});});
  }

  // === SLIDE 10: SUMMARY ===
  { const s=pres.addSlide(); s.background={color:C.navyDark}; s.addShape("rect",{x:0,y:0,w:10,h:0.06,fill:{color:C.gold}}); s.addText("总结与风险提示",{x:0.8,y:0.5,w:8.4,h:0.55,fontSize:28,fontFace:"Arial",color:C.white,bold:true,margin:0}); s.addShape("rect",{x:0.8,y:1.1,w:1.2,h:0.04,fill:{color:C.gold}});
    SUMMARY.forEach((c,i)=>{const cx=0.5+i*3.1,cy=1.4; s.addShape("rect",{x:cx,y:cy,w:2.85,h:2.2,fill:{color:C.white,transparency:92},rectRadius:0.04}); s.addText(c.title,{x:cx+0.15,y:cy+0.15,w:2.55,h:0.35,fontSize:14,fontFace:"Arial",color:C.gold,bold:true,margin:0}); s.addText(c.content,{x:cx+0.15,y:cy+0.6,w:2.55,h:1.4,fontSize:10,fontFace:"Calibri",color:C.iceBlue,margin:0,lineSpacingMultiple:1.4});});
    s.addText("⚠ 风险关注",{x:0.5,y:3.85,w:4.0,h:0.35,fontSize:16,fontFace:"Arial",color:C.accentOrange,bold:true,margin:0}); RISKS.forEach((r,i)=>{const ry=4.25+i*0.3; s.addShape("rect",{x:0.5,y:ry+0.02,w:0.1,h:0.1,fill:{color:C.accentOrange},rectRadius:0.02}); s.addText(r,{x:0.72,y:ry,w:8.8,h:0.3,fontSize:10,fontFace:"Calibri",color:C.iceBlue,margin:0});});
  }

  const outPath = `/data/hermes/workspace/exports/${new Date().toISOString().slice(0,10).replace(/-/g,"")}_${COMPANY.shortName}_客户画像报告.pptx`;
  await pres.writeFile({ fileName: outPath });
  console.log("PPT generated: " + outPath);
}

main().catch(e => { console.error("Error:", e); process.exit(1); });
