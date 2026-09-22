#!/usr/bin/env python3
"""Fallback Markdown→DOCX converter for customer-profile reports.

Use this when the primary `markdown-conversion` skill / `md2docx.py` is not
installed at the documented paths. Self-contained: only needs python-docx,
lxml and markdown.

Install deps:  pip install python-docx lxml markdown
Run:           python3 md2docx.py <input.md> <output.docx>

Handles: headings, tables (Light Grid style), bullet/numbered lists, blockquotes,
fenced code blocks, and inline **bold** / *italic* / `code`.
"""
import sys
import re
import markdown
from docx import Document
from docx.shared import Pt, RGBColor


def strip_html(s):
    s = re.sub(r'<[^>]+>', '', s)
    s = s.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>').replace('&nbsp;', ' ')
    return s.strip()


def add_table(doc, html_table):
    rows = re.findall(r'<tr[^>]*>(.*?)</tr>', html_table, re.S)
    if not rows:
        return
    first_cells = re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', rows[0], re.S)
    ncols = len(first_cells)
    if ncols == 0:
        return
    table = doc.add_table(rows=0, cols=ncols)
    table.style = 'Light Grid Accent 1'
    for r in rows:
        cells = [strip_html(c) for c in re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', r, re.S)]
        while len(cells) < ncols:
            cells.append('')
        row = table.add_row()
        for i, c in enumerate(cells[:ncols]):
            row.cells[i].text = c


def add_inline(p, text):
    for tok in re.split(r'(\*\*.*?\*\*)', text):
        if tok.startswith('**') and tok.endswith('**'):
            run = p.add_run(tok[2:-2])
            run.bold = True
        else:
            for st in re.split(r'(`[^`]*`)', tok):
                if st.startswith('`') and st.endswith('`'):
                    run = p.add_run(st[1:-1])
                    run.font.name = 'Consolas'
                    run.font.size = Pt(9)
                else:
                    p.add_run(st)


def convert(md_path, docx_path):
    with open(md_path, 'r', encoding='utf-8') as f:
        lines = f.read().split('\n')

    doc = Document()
    i = 0
    in_code = False
    code_buf = []
    table_buf = []

    def flush_table():
        nonlocal table_buf
        if table_buf:
            add_table(doc, markdown.markdown('\n'.join(table_buf), extensions=['tables']))
            table_buf = []

    def flush_code():
        nonlocal code_buf
        if code_buf:
            p = doc.add_paragraph()
            run = p.add_run('\n'.join(code_buf))
            run.font.name = 'Consolas'
            run.font.size = Pt(9)
            code_buf = []

    while i < len(lines):
        line = lines[i]
        if line.strip().startswith('```'):
            flush_table()
            if in_code:
                flush_code()
                in_code = False
            else:
                in_code = True
            i += 1
            continue
        if in_code:
            code_buf.append(line)
            i += 1
            continue
        if line.strip().startswith('|'):
            flush_code()
            table_buf.append(line)
            i += 1
            continue
        flush_table()
        stripped = line.strip()
        if re.match(r'^(-{3,}|\*{3,})$', stripped):
            i += 1
            continue
        if stripped.startswith('>'):
            flush_code()
            content = re.sub(r'^\[!.*?\]\s*', '', stripped.lstrip('>').strip())
            if content:
                p = doc.add_paragraph()
                run = p.add_run(content)
                run.italic = True
                run.font.color.rgb = RGBColor(0x66, 0x66, 0x66)
            i += 1
            continue
        m = re.match(r'^(#{1,6})\s+(.*)$', stripped)
        if m:
            flush_code()
            doc.add_heading(m.group(2).strip(), level=min(len(m.group(1)), 4))
            i += 1
            continue
        m = re.match(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$', line)
        if m:
            flush_code()
            bullet = m.group(2)
            p = doc.add_paragraph(style='List Bullet' if bullet in '-*+' else 'List Number')
            add_inline(p, m.group(3).strip())
            i += 1
            continue
        if not stripped:
            flush_code()
            i += 1
            continue
        flush_code()
        p = doc.add_paragraph()
        add_inline(p, stripped)
        i += 1

    flush_table()
    flush_code()
    doc.save(docx_path)
    print(f'OK: {docx_path}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('Usage: md2docx.py <input.md> <output.docx>')
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
