#!/usr/bin/env python3
"""Apply the small, guarded GUI changes for hybrid B32 classification."""

from __future__ import annotations

import argparse
from pathlib import Path


CLASSIFICATION_HTML = '''        <section class="classification-panel hidden" id="classification-panel">
          <div>
            <span class="eyebrow">Full model classification</span>
            <div class="classification-answer"><strong id="classification-name">—</strong><span id="classification-confidence">—</span></div>
          </div>
          <div class="classification-top" id="classification-top"></div>
          <div class="classification-timing" id="classification-timing"></div>
        </section>

'''

CLASSIFICATION_JS = '''  const classification = result.classification;
  const classificationPanel = $("#classification-panel");
  classificationPanel.classList.toggle("hidden", !classification || classification.status !== "PASS");
  if (classification && classification.status === "PASS") {
    $("#classification-name").textContent = classification.class_name;
    $("#classification-confidence").textContent = `${(100 * classification.confidence).toFixed(1)}% confidence`;
    const top = $("#classification-top");
    top.textContent = "";
    (classification.top3 || []).forEach((item, index) => {
      const row = document.createElement("div");
      row.innerHTML = `<span>${index + 1}. ${item.class_name}</span><b>${(100 * item.confidence).toFixed(1)}%</b>`;
      top.appendChild(row);
    });
    $("#classification-timing").textContent =
      `FPGA Conv1 ${classification.fpga_conv1_ms.toFixed(3)} ms + PS tail ${classification.ps_tail_ms.toFixed(3)} ms = ${classification.hybrid_compute_ms.toFixed(3)} ms`;
  }
'''

CLASSIFICATION_CSS = '''
.classification-panel { margin: 16px 0; padding: 17px 18px; border: 1px solid rgba(82,211,224,.42); border-radius: 11px; background: linear-gradient(135deg, rgba(32,109,126,.18), rgba(13,25,36,.94)); display: grid; grid-template-columns: 1fr 1.15fr; gap: 15px 24px; align-items: center; }
.classification-answer { display: flex; align-items: baseline; gap: 12px; margin-top: 5px; }
.classification-answer strong { color: #fff; font-size: clamp(1.8rem,3vw,2.7rem); text-transform: capitalize; }
.classification-answer span, .classification-timing { color: var(--muted); font-size: .76rem; }
.classification-top { display: grid; gap: 5px; }
.classification-top div { display: flex; justify-content: space-between; gap: 18px; border-bottom: 1px solid rgba(125,159,177,.18); padding: 4px 0; text-transform: capitalize; }
.classification-top b { color: var(--accent); }
.classification-timing { grid-column: 1 / -1; border-top: 1px solid rgba(125,159,177,.18); padding-top: 10px; }
@media (max-width: 720px) { .classification-panel { grid-template-columns: 1fr; } .classification-timing { grid-column: auto; } }
'''


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"expected marker missing from {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--index", type=Path, required=True)
    parser.add_argument("--javascript", type=Path, required=True)
    parser.add_argument("--css", type=Path, required=True)
    args = parser.parse_args(argv)
    for path in (args.server, args.index, args.javascript, args.css):
        if not path.is_file():
            raise FileNotFoundError(path)
        if "classification-panel" in path.read_text(encoding="utf-8"):
            raise RuntimeError(f"already patched: {path}")

    replace_once(args.server,
                 'default=Path(os.environ.get("CONV_GUI_CLI", "/home/petalinux/m8_cli.py")))',
                 'default=Path(os.environ.get("CONV_GUI_CLI", "/home/petalinux/m8_classify_cli.py")))')
    replace_once(args.server,
                 '            "output_sha256": frames[-1].get("sha256") if frames else None,',
                 '            "classification": record.get("classification"),\n'
                 '            "output_sha256": frames[-1].get("sha256") if frames else None,')
    replace_once(args.index, '        <div class="gallery-wrap hidden" id="gallery-wrap">',
                 CLASSIFICATION_HTML + '        <div class="gallery-wrap hidden" id="gallery-wrap">')
    replace_once(args.javascript, '  const gallery = $("#gallery");',
                 CLASSIFICATION_JS + '  const gallery = $("#gallery");')
    with args.css.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(CLASSIFICATION_CSS)
    print("GUI CLASSIFICATION PATCH: APPLIED")


if __name__ == "__main__":
    main()
