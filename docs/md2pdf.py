#!/usr/bin/env python3
"""md2pdf.py - render a Markdown document to PDF (WeasyPrint, A4).

One renderer for the whole workspace. The predecessor repository carried three
copies of this script -- root, 32b and 64b -- differing only in the title page
and the running footer, so those are arguments here instead of edits.

    python3 docs/md2pdf.py in.md out.pdf \\
        --title    "SMP Construction" \\
        --subtitle "How the kernel, the ports and the tests fit together" \\
        --footer   "micro-os-plus-iii-smp" \\
        --meta     "Kernel:micro-os-plus-iii (SMP scheduler)"

--toc prepends a contents list built from the H1 and H2 headings, which is what
`pandoc --toc --toc-depth=2` used to give the documents under docs/tests/.

Requires: python-markdown, weasyprint.
"""
import argparse
import html
import sys

import markdown
from weasyprint import HTML

CSS = """
    @page {
        size: A4;
        margin: 20mm;
        @bottom-right {
            content: "Page " counter(page) " of " counter(pages);
            font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
            font-size: 8pt;
            color: #718096;
        }
        @bottom-left {
            content: "__FOOTER__";
            font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
            font-size: 8pt;
            color: #718096;
        }
    }
    body {
        font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
        color: #2d3748;
        line-height: 1.6;
        font-size: 10pt;
    }
    h1, h2, h3, h4, h5, h6 {
        color: #1a365d;
        font-weight: 700;
        page-break-after: avoid;
    }
    h1 {
        font-size: 22pt;
        border-bottom: 2px solid #2b6cb0;
        padding-bottom: 6px;
        margin-top: 0;
        margin-bottom: 20px;
    }
    h2 {
        font-size: 16pt;
        border-bottom: 1px solid #e2e8f0;
        padding-bottom: 4px;
        margin-top: 30px;
        margin-bottom: 12px;
    }
    h3 {
        font-size: 12pt;
        margin-top: 20px;
        margin-bottom: 8px;
    }
    p {
        margin-bottom: 12px;
        text-align: justify;
    }
    code {
        font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, Courier, monospace;
        background-color: #f7fafc;
        padding: 2px 4px;
        border-radius: 4px;
        font-size: 8.5pt;
        border: 1px solid #e2e8f0;
        color: #c53030;
    }
    pre {
        background-color: #f7fafc;
        border: 1px solid #e2e8f0;
        border-radius: 6px;
        padding: 12px;
        overflow: auto;
        page-break-inside: avoid;
        margin-bottom: 15px;
    }
    pre code {
        background-color: transparent;
        border: none;
        padding: 0;
        border-radius: 0;
        font-size: 7.5pt;
        color: #2d3748;
        white-space: pre-wrap;
        word-wrap: break-word;
    }
    table {
        width: 100%;
        border-collapse: collapse;
        margin-top: 15px;
        margin-bottom: 20px;
        page-break-inside: avoid;
        table-layout: fixed;
    }
    th, td {
        border: 1px solid #cbd5e0;
        padding: 6px 7px;
        text-align: left;
        font-size: 8pt;
        vertical-align: top;
        overflow-wrap: anywhere;
        word-break: break-word;
    }
    td code, th code {
        white-space: normal;
        overflow-wrap: anywhere;
        word-break: break-word;
        font-size: 7.5pt;
    }
    th {
        background-color: #ebf8ff;
        color: #2b6cb0;
        font-weight: bold;
    }
    tr:nth-child(even) {
        background-color: #f7fafc;
    }
    blockquote {
        margin: 15px 0;
        padding: 8px 15px;
        background-color: #ebf8ff;
        border-left: 4px solid #3182ce;
        color: #2b6cb0;
    }
    ul, ol {
        margin-bottom: 12px;
        padding-left: 24px;
    }
    ol {
        padding-left: 28px;
    }
    li {
        margin-bottom: 5px;
        text-align: justify;
        padding-left: 2px;
    }
    li > ul, li > ol {
        margin-top: 5px;
        margin-bottom: 5px;
    }
    li > p {
        margin-bottom: 6px;
        text-align: justify;
    }
    .toc {
        page-break-after: always;
        margin-bottom: 20px;
    }
    .toc > ul {
        padding-left: 0;
        list-style: none;
    }
    .toc ul ul {
        padding-left: 18px;
    }
    .toc li {
        margin-bottom: 3px;
        text-align: left;
    }
    .toc a {
        color: #2b6cb0;
        text-decoration: none;
    }
    .title-page {
        page-break-after: always;
        text-align: center;
        padding-top: 40mm;
    }
    .title-page h1 {
        font-size: 28pt;
        color: #1a365d;
        border: none;
        margin-bottom: 15px;
    }
    .title-page h2 {
        font-size: 16pt;
        color: #4a5568;
        border: none;
        margin-bottom: 60px;
    }
    .title-page .meta {
        margin-top: 60mm;
        font-size: 11pt;
        color: #4a5568;
        line-height: 1.8;
    }
    .title-page .meta p {
        text-align: center;
        margin-bottom: 5px;
    }
    """


def render(md_path, pdf_path, title=None, subtitle=None, footer="", meta=None,
           toc=False):
    with open(md_path, "r", encoding="utf-8") as f:
        text = f.read()

    if toc:
        text = "[TOC]\n\n" + text

    body = markdown.markdown(
        text, extensions=["extra", "codehilite", "toc"],
        extension_configs={"toc": {"toc_depth": "1-2"}})
    doc = ("<html><head><meta charset='utf-8'>"
           # WeasyPrint takes the PDF's Title metadata from this element.
           + ("<title>" + html.escape(title) + "</title>" if title else "")
           + "<style>"
           + CSS.replace("__FOOTER__", footer)
           + "</style></head><body>")

    if title:
        doc += '<div class="title-page">'
        doc += "<h1>" + html.escape(title) + "</h1>"
        if subtitle:
            doc += "<h2>" + html.escape(subtitle) + "</h2>"
        if meta:
            doc += '<div class="meta">'
            for entry in meta:
                key, _, value = entry.partition(":")
                doc += ("<p><strong>" + html.escape(key.strip()) + ":</strong> "
                        + html.escape(value.strip()) + "</p>")
            doc += "</div>"
        doc += "</div>"

    HTML(string=doc + body + "</body></html>").write_pdf(pdf_path)
    print(pdf_path)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--title")
    ap.add_argument("--subtitle")
    ap.add_argument("--footer", default="")
    ap.add_argument("--meta", action="append", metavar="KEY:VALUE",
                    help="a title-page line; repeatable")
    ap.add_argument("--toc", action="store_true",
                    help="prepend a contents list of the H1 and H2 headings")
    a = ap.parse_args()
    render(a.input, a.output, a.title, a.subtitle, a.footer, a.meta, a.toc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
