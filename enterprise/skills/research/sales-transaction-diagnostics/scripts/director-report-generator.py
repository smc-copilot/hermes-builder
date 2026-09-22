#!/usr/bin/env python3
"""
Director-Level Business Data Analysis Report Generator (python-docx)
生成结构化Word报告：执行摘要、业务全景、客户分析、产品分析、销售绩效、
业务模式透视、退货分析、SWOT、风险预警、战略建议、总监洞察

前置条件:
  pip install python-docx

用法:
  from docx import Document
  from docx.shared import Inches, Pt, Cm, RGBColor
  from docx.enum.text import WD_ALIGN_PARAGRAPH
  from docx.oxml.ns import qn
  
  doc = Document()
  # ... 使用下方函数构建报告 ...
  doc.save('output.docx')
"""

from docx import Document
from docx.shared import Inches, Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
import datetime

def setup_chinese_font(doc, font_name='Microsoft YaHei', font_size=Pt(11)):
    """设置中文文档默认字体"""
    style = doc.styles['Normal']
    font = style.font
    font.name = 'Calibri'
    font.size = font_size
    style.element.rPr.rFonts.set(qn('w:eastAsia'), font_name)
    return doc

def add_kpi_table(doc, headers, data, style='Light Grid Accent 1'):
    """添加格式化数据表，首行加粗居中"""
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = style
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    
    hdr = table.rows[0]
    for i, h in enumerate(headers):
        hdr.cells[i].text = h
        for p in hdr.cells[i].paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            for run in p.runs:
                run.font.bold = True
                run.font.size = Pt(10)
    
    for row_data in data:
        row = table.add_row()
        for i, val in enumerate(row_data):
            row.cells[i].text = str(val)
            for p in row.cells[i].paragraphs:
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                for run in p.runs:
                    run.font.size = Pt(10)
    
    return table

def add_highlight(doc, text, color='blue'):
    """添加加粗高亮文字段落"""
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.font.bold = True
    colors = {'red': (0xCC, 0x00, 0x00), 'green': (0x00, 0x80, 0x00),
              'orange': (0xFF, 0x8C, 0x00), 'blue': (0x00, 0x52, 0x8B)}
    c = colors.get(color, (0x00, 0x52, 0x8B))
    run.font.color.rgb = RGBColor(*c)
    return p

def add_bullet_list(doc, items):
    """添加无序列表"""
    for item in items:
        doc.add_paragraph(item, style='List Bullet')

def create_swot_table(doc, swot_data):
    """创建SWOT四象限表格"""
    # swot_data: {'S': [strengths], 'W': [weaknesses], 'O': [opportunities], 'T': [threats]}
    table = doc.add_table(rows=3, cols=3)
    table.style = 'Light Grid Accent 1'
    
    def fill_cell(row, col, title, items, color):
        cell = table.cell(row, col)
        cell.text = title
        for p in cell.paragraphs:
            if p.runs:
                p.runs[0].font.bold = True
                p.runs[0].font.color.rgb = RGBColor(*color)
        # Add items
        for item in items:
            p = cell.add_paragraph(f'• {item}')
            p.style.font.size = Pt(9)
    
    fill_cell(0, 0, '优势 (Strengths)', swot_data.get('S', []), (0x00, 0x52, 0x8B))
    fill_cell(0, 1, '劣势 (Weaknesses)', swot_data.get('W', []), (0xCC, 0x00, 0x00))
    fill_cell(0, 2, '机会 (Opportunities)', swot_data.get('O', []), (0x00, 0x80, 0x00))
    
    # Threats span 2 cells
    cell = table.cell(2, 0)
    cell.text = '威胁 (Threats)'
    for p in cell.paragraphs:
        if p.runs:
            p.runs[0].font.bold = True
            p.runs[0].font.color.rgb = RGBColor(0xFF, 0x8C, 0x00)
    for item in swot_data.get('T', []):
        p = cell.add_paragraph(f'• {item}')
        p.style.font.size = Pt(9)
    cell_t = table.cell(2, 1)
    cell.merge(cell_t)
    
    return table

def create_risk_matrix(doc, risks):
    """创建风险预警清单表
    risks: [(编号, 风险项, 严重度, 状态, 描述, 应对策略)]
    """
    headers = ['编号', '风险项', '严重度', '状态', '描述', '应对策略']
    return add_kpi_table(doc, headers, risks)

def create_cover_page(doc, title_text, subtitle_text, date_text=None, level='机密'):
    """创建报告封面"""
    for _ in range(6):
        doc.add_paragraph('')
    
    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = title.add_run(title_text)
    run.font.size = Pt(26)
    run.font.bold = True
    run.font.color.rgb = RGBColor(0x1A, 0x1A, 0x2E)
    
    doc.add_paragraph('')
    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = subtitle.add_run(subtitle_text)
    run.font.size = Pt(14)
    run.font.color.rgb = RGBColor(0x66, 0x66, 0x66)
    
    for _ in range(4):
        doc.add_paragraph('')
    
    info = doc.add_paragraph()
    info.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = info.add_run(f'报告类型：总监级深度研究报告\n')
    run.font.size = Pt(12)
    run = info.add_run(f'报告日期：{date_text or datetime.date.today().strftime("%Y年%m月%d日")}\n')
    run.font.size = Pt(12)
    run = info.add_run(f'密级：{level}')
    run.font.size = Pt(12)
    run.font.color.rgb = RGBColor(0xCC, 0x00, 0x00)
    
    doc.add_page_break()
    return doc

def create_toc_page(doc, items):
    """创建目录页
    items: [(标题, 页码)]
    """
    doc.add_heading('目 录', level=1)
    for title, page in items:
        p = doc.add_paragraph()
        run = p.add_run(f'{title}')
        run.font.size = Pt(11)
    doc.add_page_break()
    return doc

def create_executive_summary(doc, summary_items, findings=None):
    """创建执行摘要"""
    doc.add_heading('一、执行摘要', level=1)
    
    for p_text in summary_items:
        p = doc.add_paragraph(p_text)
    
    if findings:
        p = doc.add_paragraph()
        p.add_run('核心发现：').font.bold = True
        for f in findings:
            doc.add_paragraph(f, style='List Bullet')
    
    return doc

def create_director_insight(doc, insights):
    """创建总监洞察章节
    insights: [(标题, 正文)]
    """
    doc.add_heading('总监洞察 (Director\'s Insight)', level=1)
    
    for title, body in insights:
        p = doc.add_paragraph()
        run = p.add_run(title)
        run.font.bold = True
        run.font.size = Pt(13)
        run.font.color.rgb = RGBColor(0x00, 0x52, 0x8B)
        
        doc.add_paragraph(body)
    
    return doc


# ============================================================
# 完整报告生成示例
# ============================================================
if __name__ == '__main__':
    """生成示范报告"""
    doc = Document()
    setup_chinese_font(doc)
    
    create_cover_page(doc, 
        '电商中心2023年业务数据深度研究报告',
        '——多维度业务诊断、隐藏优势与风险识别、发展潜力评估',
        level='内部机密')
    
    create_toc_page(doc, [
        ('一、执行摘要', 2),
        ('二、业务全景总览', 3),
        ('三、客户维度深度诊断', 4),
        ('四、销售团队绩效评估', 5),
        ('五、产品与业务模式分析', 6),
        ('六、SWOT与风险预警', 7),
        ('七、总监洞察', 8),
    ])
    
    create_executive_summary(doc,
        ['本报告对电商中心2023年度全量业务数据进行了跨维度深度诊断。'],
        [
            '【结构风险】客户集中度极高——Top1客户占43.8%，Top3客户占72%',
            '【盈利困境】整体毛利率仅10.9%，毛利覆盖率23.4%，距盈亏平衡尚远',
            '【增长瓶颈】43%客户仅为单次交易，产品多元化不足',
            '【隐性优势】自营平台完全可控、零平台佣金，团队全链路闭环',
        ])
    
    doc.save('/tmp/demo_report.docx')
    print("Demo report generated: /tmp/demo_report.docx")
    print("Usage: import this module and call the helper functions")
    print(f"\nAvailable functions:")
    print(f"  setup_chinese_font(doc)")
    print(f"  add_kpi_table(doc, headers, data)")
    print(f"  add_highlight(doc, text, color)")
    print(f"  add_bullet_list(doc, items)")
    print(f"  create_swot_table(doc, swot_data)")
    print(f"  create_risk_matrix(doc, risks)")
    print(f"  create_cover_page(doc, title, subtitle, date, level)")
    print(f"  create_executive_summary(doc, paragraphs, findings)")
    print(f"  create_director_insight(doc, insights)")
