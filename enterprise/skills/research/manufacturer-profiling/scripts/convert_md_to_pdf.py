#!/usr/bin/env python3
"""
Convert a Markdown report to a professional A4 PDF with CJK (Chinese) support.

Usage:
    python3 convert_md_to_pdf.py <input.md> [output.pdf]

Dependencies (pip install if missing):
    pip install markdown weasyprint

Font required:
    Noto Sans CJK SC (Simplified Chinese OTF)
    Download URL: https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf
    This script will auto-download if the font is not found at the expected path.

CSS features:
    - A4 page size with 1.8cm margins
    - Page header (report title) on all pages except first
    - Page footer with centered page numbers
    - Professional table styling: dark header, zebra-striped rows
    - Heading hierarchy with color-coded levels (#1a3a5c palette)
    - Blockquote styling with left border
    - Code blocks with monospace font
    - Page-break avoidance for tables, headings, and list items
"""

import markdown
import re
import os
import sys
import urllib.request
from weasyprint import HTML

# ---- Configuration ----
FONT_DIR = os.path.expanduser("~/.fonts")
FONT_FILE = "NotoSansCJKsc-Regular.otf"
FONT_URL = "https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf"
FONT_PATH = os.path.join(FONT_DIR, FONT_FILE)


def ensure_font():
    """Download CJK font if not already present."""
    if os.path.exists(FONT_PATH):
        print(f"Font found: {FONT_PATH}")
        return

    print(f"Downloading CJK font (~16MB) from {FONT_URL}...")
    os.makedirs(FONT_DIR, exist_ok=True)

    req = urllib.request.Request(FONT_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read()
        if len(data) < 100_000:
            raise RuntimeError(f"Downloaded font is too small ({len(data)} bytes) — likely an error page")
        with open(FONT_PATH, "wb") as f:
            f.write(data)
    print(f"Font saved: {FONT_PATH} ({len(data):,} bytes)")


def clean_markdown(content: str) -> str:
    """Remove YAML frontmatter and mermaid blocks."""
    # Remove YAML frontmatter (between --- delimiters at start)
    content = re.sub(r"^---\n.*?\n---\n", "", content, flags=re.DOTALL, count=1)
    # Remove mermaid diagram blocks (can't render in static PDF)
    content = re.sub(r"```mermaid\n.*?\n```", "", content, flags=re.DOTALL)
    return content


def build_html(body: str, font_path: str) -> str:
    """Wrap converted HTML body in a full document with professional CSS."""
    # Fix table class for styling
    body = body.replace("<table>", '<table class="data-table">')

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<style>
@page {{
    size: A4;
    margin: 1.8cm 1.5cm 2.0cm 1.5cm;
    @bottom-center {{
        content: "— " counter(page) " —";
        font-family: "Noto Sans CJK SC", sans-serif;
        font-size: 9pt;
        color: #888;
    }}
    @top-right {{
        content: string(doctitle);
        font-family: "Noto Sans CJK SC", sans-serif;
        font-size: 8pt;
        color: #aaa;
    }}
}}

@page :first {{
    @top-right {{
        content: none;
    }}
}}

@font-face {{
    font-family: "Noto Sans CJK SC";
    src: url("file://{font_path}") format("opentype");
}}

body {{
    font-family: "Noto Sans CJK SC", "SimSun", "Microsoft YaHei", sans-serif;
    font-size: 10.5pt;
    line-height: 1.75;
    color: #222;
}}

h1 {{
    string-set: doctitle content();
    font-size: 20pt;
    color: #1a3a5c;
    text-align: center;
    padding: 30px 0 10px 0;
    border-bottom: 3px solid #1a3a5c;
    margin-bottom: 20px;
    page-break-before: avoid;
}}

h2 {{
    font-size: 14pt;
    color: #1a3a5c;
    margin-top: 28px;
    margin-bottom: 12px;
    padding-bottom: 4px;
    border-bottom: 1.5px solid #c0d0e0;
    page-break-after: avoid;
}}

h3 {{
    font-size: 12pt;
    color: #2d5a88;
    margin-top: 20px;
    margin-bottom: 8px;
    page-break-after: avoid;
}}

h4 {{
    font-size: 11pt;
    color: #3a6a9e;
    margin-top: 16px;
    margin-bottom: 6px;
    page-break-after: avoid;
}}

.data-table {{
    width: 100%;
    border-collapse: collapse;
    margin: 12px 0 16px 0;
    font-size: 9.5pt;
    page-break-inside: avoid;
}}

.data-table thead th {{
    background-color: #1a3a5c;
    color: white;
    font-weight: 600;
    padding: 7px 8px;
    text-align: left;
    font-size: 9pt;
}}

.data-table tbody td {{
    padding: 6px 8px;
    border-bottom: 1px solid #ddd;
    border-right: 1px solid #eee;
    vertical-align: top;
}}

.data-table tbody tr:nth-child(even) {{
    background-color: #f7f9fb;
}}

blockquote {{
    margin: 14px 0;
    padding: 10px 16px;
    border-left: 4px solid #1a3a5c;
    background: #f0f4f8;
    font-size: 10pt;
    color: #444;
}}

blockquote p {{
    margin: 2px 0;
}}

code {{
    font-family: "DejaVu Sans Mono", monospace;
    font-size: 9pt;
    background: #f5f5f5;
    padding: 1px 4px;
    border-radius: 3px;
}}

pre {{
    background: #f8f8f8;
    border: 1px solid #e0e0e0;
    border-left: 3px solid #1a3a5c;
    padding: 10px 14px;
    font-size: 9pt;
    overflow-x: auto;
    page-break-inside: avoid;
}}

pre code {{
    background: none;
    padding: 0;
}}

p {{
    margin: 6px 0;
    text-align: justify;
}}

strong {{
    color: #1a3a5c;
}}

h2, h3, h4 {{
    page-break-after: avoid;
}}

tr {{
    page-break-inside: avoid;
}}

hr {{
    border: none;
    border-top: 1px dotted #ccc;
    margin: 20px 0;
}}
</style>
</head>
<body>
{body}
</body>
</html>"""


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 convert_md_to_pdf.py <input.md> [output.pdf]")
        sys.exit(1)

    md_path = sys.argv[1]
    if not os.path.exists(md_path):
        print(f"Error: file not found: {md_path}")
        sys.exit(1)

    # Default output: same basename, .pdf extension
    pdf_path = sys.argv[2] if len(sys.argv) >= 3 else md_path.rsplit(".", 1)[0] + ".pdf"

    # Ensure CJK font is available
    ensure_font()

    # Read markdown
    with open(md_path, "r", encoding="utf-8") as f:
        md_content = f.read()

    # Clean
    md_content = clean_markdown(md_content)

    # Convert MD → HTML
    html_body = markdown.markdown(
        md_content, extensions=["tables", "fenced_code", "nl2br", "sane_lists"]
    )

    # Build full HTML document
    html_doc = build_html(html_body, FONT_PATH)

    # Generate PDF
    print(f"Converting {md_path} → {pdf_path} ...")
    HTML(string=html_doc).write_pdf(pdf_path)

    size_kb = os.path.getsize(pdf_path) / 1024
    print(f"Done. PDF: {pdf_path} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()