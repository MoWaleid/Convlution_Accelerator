"""Generate report figures 2 (pipeline) and 3 (FSM) from the RTL structure.
Run: python generate_figures.py  (writes PNGs next to this script)."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

STAGES = [
    ("S1 MULTIPLY", "9x uint8 x int8\n-> 9x signed 17-bit\n(use_dsp = no: LUTs)"),
    ("S2 ADD-TREE L1", "9 products -> 3\npartial sums\nsigned 19-bit"),
    ("S3 ADD-TREE L2 + BIAS", "3 partials -> 1 sum\n+ 24-bit bias\nsigned 25-bit"),
    ("S4 POST-PROCESS", "round-half-up\nsaturate int16\nReLU (per-channel)"),
]

fig, ax = plt.subplots(figsize=(12.5, 3.2), dpi=200)
ax.axis("off")
bw, bh, gap = 2.6, 1.7, 0.55
x0, y0 = 0.4, 0.8
ax.annotate("from window generator:\n3x3 window (shared, 8 channels)", xy=(x0, y0 + bh / 2),
            xytext=(x0 - 0.05, y0 + bh + 0.45), fontsize=9, ha="left", color="#444444")
for i, (title, body) in enumerate(STAGES):
    x = x0 + i * (bw + gap)
    box = FancyBboxPatch((x, y0), bw, bh, boxstyle="round,pad=0.08",
                         fc="#eef3fb", ec="#2c5aa0", lw=1.6)
    ax.add_patch(box)
    ax.text(x + bw / 2, y0 + bh - 0.33, title, ha="center", fontsize=10.5, weight="bold")
    ax.text(x + bw / 2, y0 + bh / 2 - 0.22, body, ha="center", va="center", fontsize=8.6)
    if i:
        ax.add_patch(FancyArrowPatch((x - gap, y0 + bh / 2), (x, y0 + bh / 2),
                                     arrowstyle="-|>", mutation_scale=16, color="#2c5aa0", lw=1.6))
    else:
        ax.add_patch(FancyArrowPatch((x0 - 0.55, y0 + bh / 2), (x, y0 + bh / 2),
                                     arrowstyle="-|>", mutation_scale=16, color="#2c5aa0", lw=1.6))
xe = x0 + 4 * (bw + gap)
ax.add_patch(FancyArrowPatch((xe - gap, y0 + bh / 2), (xe + 0.15, y0 + bh / 2),
                             arrowstyle="-|>", mutation_scale=16, color="#2c5aa0", lw=1.6))
ax.text(xe + 0.25, y0 + bh / 2, "int16 result\n(1 channel result\nper clock)", fontsize=9, va="center")
ax.annotate("valid/enable pipelined alongside data (4-cycle latency)", xy=(x0, y0 - 0.25),
            fontsize=9, color="#666666")
ax.set_xlim(-0.2, xe + 2.2)
ax.set_ylim(0.1, y0 + bh + 0.9)
fig.tight_layout()
fig.savefig("fig2_pipeline.png", bbox_inches="tight")
plt.close(fig)

# FSM
fig, ax = plt.subplots(figsize=(11.5, 5.6), dpi=200)
ax.axis("off")
states = {"IDLE": (1.8, 3.2), "RUN": (8.4, 4.7), "FAULT": (8.4, 1.6)}
colors = {"IDLE": "#e8f5e9", "RUN": "#eef3fb", "FAULT": "#fdecea"}
for name, (x, y) in states.items():
    ax.add_patch(FancyBboxPatch((x - 1.0, y - 0.55), 2.0, 1.1, boxstyle="round,pad=0.1",
                                fc=colors[name], ec="#333333", lw=1.6))
    ax.text(x, y, name, ha="center", va="center", fontsize=14, weight="bold")

def arrow(a, b, label, rad=0.0, lx=None, ly=None):
    (x1, y1), (x2, y2) = states[a], states[b]
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), connectionstyle=f"arc3,rad={rad}",
                                 arrowstyle="-|>", mutation_scale=15, color="#555555", lw=1.4))
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    ax.text(lx if lx else mx, ly if ly else my, label, fontsize=8.6, ha="center",
            color="#333333",
            bbox=dict(fc="white", ec="none", alpha=0.88, pad=1.2))

arrow("IDLE", "RUN", "START (cmd 1):\nIDLE + QUIESCENT\n+ PARAM_COMPLETE\n+ zero errors",
      rad=-0.32, lx=4.1, ly=5.15)
arrow("RUN", "IDLE", "frame complete:\ncounters == quotas,\nCORE_COMPLETE\n-> DONE + OUTPUT_DRAINED",
      rad=-0.32, lx=4.6, ly=2.9)
arrow("RUN", "FAULT", "ABORT (cmd 4) |\ninternal invariant |\nquota without TLAST",
      rad=-0.35, lx=10.6, ly=3.2)
arrow("FAULT", "IDLE", "RESET (cmd 2):\nclears counters, events,\nerrors; KEEPS parameters",
      rad=-0.12, lx=4.6, ly=1.0)
ax.annotate("ABORT is legal from any state and always -> FAULT", xy=(6.6, 0.75),
            fontsize=8.6, color="#666666")
ax.annotate("full-PL reload resets fabric to STATUS 0x101", xy=(0.5, 4.9),
            fontsize=8.6, color="#666666")
ax.set_xlim(0.2, 12.0)
ax.set_ylim(0.5, 5.7)
fig.tight_layout()
fig.savefig("fig3_fsm.png", bbox_inches="tight")
plt.close(fig)
print("figures written")
