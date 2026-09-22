#!/usr/bin/env node
/**
 * Customer Profiling PPT Template
 * 
 * Generates a 10-slide customer analysis PPT using pptxgenjs.
 * Usage: 
 *   1. Fill in the CUSTOMER object below with your profiling data
 *   2. npm install pptxgenjs (in workspace dir)
 *   3. node this_script.js
 *
 * Output: /data/hermes/workspace/exports/sale/{shortName}_客户情况分析.pptx
 */

const pptxgen = require("pptxgenjs");

// ============================================================
// FILL IN: Customer data from profiling report
// ============================================================
const CUSTOMER = {
  fullName: "XX科技有限公司",
  shortName: "XX科技",
  founded: "YYYY-MM-DD",
  legalRep: "张三",
  address: "XX市XX区",
  qualifications: ["国家高新技术企业", "广东省专精特新企业"],
  employeeEstimate: "推测50~200人",
  businessSummary: "公司简介段落...",
  bizLines: [
    { icon: "🚗", title: "业务线1", desc: "描述" },
    { icon: "📷", title: "业务线2", desc: "描述" },
    { icon: "🏠", title: "业务线3", desc: "描述" },
  ],
  products: [
    ["品类", "产品名", "是", "说明"],
  ],
  capabilities: [
    { num: "01", title: "能力1", desc: "描述" },
    { num: "02", title: "能力2", desc: "描述" },
  ],
  techAreas: [
    { area: "领域", chips: "芯片品类", level: "核心能力/发展中/基础能力" },
  ],
  supplyLayers: [
    { tier: "层级", supplier: "供应商", role: "角色", space: "盲区" },
  ],
  chipTiers: [
    { stars: "★★★", label: "核心", color: "0D9488", items: "品类列表" },
    { stars: "★★☆", label: "扩展", color: "EA580C", items: "品类列表" },
  ],
  coreChips: [
    ["品类", "品牌", "逻辑", "规模估算"],
  ],
  extChips: ["品类 - 描述"],
  score: { total: 68, max: 110, grade: "B", strategy: "策略说明", dim1: "28/55", dim2: "22/30", dim3: "11/15", bonus: "+7" },
  bizSummary: { scale: "$50~150万", urgency: "中", barrier: "中低" },
  entrySteps: [
    { step: "STEP 1", desc: "描述", note: "细节" },
  ],
  priorityItems: [
    { priority: "P0", product: "产品", reason: "理由", cycle: "1~2月", amount: "$X万" },
  ],
  risks: [
    { level: "中", color: "EA580C", title: "风险项", desc: "描述", action: "对策" },
  ],
  dataGapsNote: "未核实数据项列表...",
  oneLiner: "一句话判断...",
};

// ============================================================
// Color Palette (Ocean Gradient)
// ============================================================
const C = {
  dark: "065A82", mid: "1C7293", midnight: "21295C",
  white: "FFFFFF", offWhite: "F2F6F9", lightGray: "E8EDF2",
  text: "1E293B", subtext: "64748B", accent: "0891B2",
  green: "0D9488", orange: "EA580C", red: "DC2626", amber: "D97706"
};

// ============================================================
// Build
// ============================================================
const pres = new pptxgen();
pres.layout = "LAYOUT_16x9";
pres.author = "Hermes Agent";
pres.title = `${CUSTOMER.fullName} 客户情况分析`;

function addTitleBar(slide, title, subtitle) {
  slide.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: 10, h: 1.15, fill: { color: C.dark } });
  slide.addText(title, { x: 0.6, y: 0.15, w: 8.8, h: 0.55, fontSize: 26, fontFace: "Microsoft YaHei", color: C.white, bold: true, margin: 0 });
  if (subtitle) slide.addText(subtitle, { x: 0.6, y: 0.68, w: 8.8, h: 0.35, fontSize: 12, fontFace: "Microsoft YaHei", color: "CADCFC", margin: 0 });
}
function addFooter(slide, pageNum) {
  slide.addShape(pres.shapes.LINE, { x: 0.6, y: 5.25, w: 8.8, h: 0, line: { color: C.lightGray, width: 0.5 } });
  slide.addText(`${CUSTOMER.fullName}  |  客户情况分析`, { x: 0.6, y: 5.3, w: 5, h: 0.25, fontSize: 8, fontFace: "Microsoft YaHei", color: C.subtext, margin: 0 });
  slide.addText(`${pageNum}`, { x: 8.5, y: 5.3, w: 0.9, h: 0.25, fontSize: 8, fontFace: "Microsoft YaHei", color: C.subtext, align: "right", margin: 0 });
}

// Slide 1: Cover
const s1 = pres.addSlide();
s1.background = { color: C.dark };
s1.addText(CUSTOMER.fullName, { x: 1, y: 1.2, w: 8, h: 0.9, fontSize: 40, fontFace: "Microsoft YaHei", color: C.white, bold: true, align: "center", margin: 0 });
s1.addText("客户情况分析报告", { x: 1, y: 2.15, w: 8, h: 0.6, fontSize: 28, fontFace: "Microsoft YaHei", color: "CADCFC", align: "center", margin: 0 });
s1.addShape(pres.shapes.LINE, { x: 3, y: 2.95, w: 4, h: 0, line: { color: C.accent, width: 3 } });
s1.addText(CUSTOMER.qualifications.join("  |  "), { x: 1, y: 3.2, w: 8, h: 0.4, fontSize: 13, fontFace: "Microsoft YaHei", color: "94A3B8", align: "center", margin: 0 });
s1.addText(`2026年8月  |  机密`, { x: 1, y: 4.7, w: 8, h: 0.4, fontSize: 11, fontFace: "Microsoft YaHei", color: "64748B", align: "center", margin: 0 });

console.log(`Generating PPT for ${CUSTOMER.fullName}...`);
// (Add remaining slides here following the same pattern as create_ouli_ppt.js)

const outputPath = `/data/hermes/workspace/exports/sale/${CUSTOMER.shortName}_客户情况分析.pptx`;
pres.writeFile({ fileName: outputPath })
  .then(() => console.log(`✅ PPT saved to: ${outputPath}`))
  .catch(err => console.error("Error:", err));
