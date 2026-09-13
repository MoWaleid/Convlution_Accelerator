#!/usr/bin/env python3
"""Regenerate report/report.html from report/report.md, preserving the
established print-ready style block and title from the previous HTML."""
import re
from pathlib import Path

import markdown

HERE = Path(__file__).resolve().parent
md_text = (HERE / "report.md").read_text(encoding="utf-8")
old = (HERE / "report.html").read_text(encoding="utf-8")

style = re.search(r"<style>.*?</style>", old, re.S).group(0)
title = re.search(r"<title>(.*?)</title>", old).group(1)
body = markdown.markdown(md_text, extensions=["tables"])


def inline_images(html):
    """Embed every referenced image as a base64 data URI so the HTML is a
    self-contained submission artifact."""
    import base64

    def repl(m):
        path = m.group(1)
        f = (HERE / path).resolve()
        if not f.is_file():
            print(f"WARNING: image missing, left as path: {path}")
            return m.group(0)
        data = base64.b64encode(f.read_bytes()).decode()
        return f'src="data:image/png;base64,{data}"'

    return re.sub(r'src="([^"]+)"', repl, html)


body = inline_images(body)
html = ('<!DOCTYPE html><html><head><meta charset="utf-8">\n'
        f"<title>{title}</title>\n{style}</head><body>\n{body}\n</body></html>\n")
(HERE / "report.html").write_text(html, encoding="utf-8")
print("report.html regenerated:", len(html), "bytes")
