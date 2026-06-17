#!/usr/bin/env python3
"""figs/hof.png — map / filter / reduce as one shape: a counted loop over the buffer that calls
the closure (a thick function) per element. map collects every result; filter collects the ones
the predicate keeps; reduce folds them into one accumulator. Closures (29) meet containers (31)."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"
SRC = "#eef2f7"; CLO = "#e6dcf5"; OUT = "#dceede"; ACC = "#fde8d6"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.6, mono=True):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.06",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.30
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=9.0, fontweight="bold", color=TEXT, zorder=4)
        ty -= 0.40
    fam = "monospace" if mono else "sans-serif"
    for ln in lines:
        ax.text(x + w / 2, ty, ln, ha="center", fontsize=fs, family=fam, color=TEXT, zorder=4)
        ty -= 0.34


def arr(ax, p0, p1, color="#b5651d", label=None, dx=0, dy=0.13, fs=8.0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.7,
                 color=color, zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center",
                fontsize=fs, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(12.4, 6.6))
    ax.set_xlim(0, 13); ax.set_ylim(0, 7); ax.axis("off")
    ax.text(6.5, 6.75, "map / filter / reduce — one shape: walk the buffer, call the closure per element",
            ha="center", fontsize=11.5, fontweight="bold", color=TEXT)

    # the source buffer
    box(ax, 0.4, 4.3, 2.4, 1.4, ["[ e0, e1, e2, … ]"], SRC, title="source buffer (31)", fs=8.4)
    # the closure
    box(ax, 0.4, 2.0, 2.4, 1.4, ["code ptr", "context ptr"], CLO, title="closure  %thickfn (29)", fs=8.4)
    # the loop
    box(ax, 3.5, 2.7, 3.0, 2.6,
        ["for i in 0..<count:", "  elt = array_get(i)", "  r = apply_value(", "        clo, [elt])", "  …use r…"],
        "#f3f6fa", title="counted loop (silgen)", fs=8.2)
    arr(ax, (2.8, 5.0), (3.5, 4.6), label="elements")
    arr(ax, (2.8, 2.7), (3.5, 3.4), label="called per elt")

    # three outcomes
    box(ax, 7.4, 5.0, 5.0, 1.3, ["push r -> [f(e0), f(e1), f(e2), …]"], OUT,
        title="map  ->  [R]   (collect every result)", fs=8.2)
    box(ax, 7.4, 3.3, 5.0, 1.3, ["if r { push elt } -> kept elements"], OUT,
        title="filter  ->  [E]   (keep where r is true)", fs=8.2)
    box(ax, 7.4, 1.6, 5.0, 1.3, ["acc = r  ->  one folded value"], ACC,
        title="reduce  ->  R   (fold into an accumulator)", fs=8.2)
    arr(ax, (6.5, 4.4), (7.4, 5.6), color="#2a8", dy=0.16)
    arr(ax, (6.5, 4.0), (7.4, 3.95), color="#2a8")
    arr(ax, (6.5, 3.6), (7.4, 2.3), color="#a14a00", dy=-0.18)

    ax.text(6.5, 0.75,
            "No new SIL, no new runtime — apply_value (the closure ABI) + the array buffer intrinsics. swiftc's Sequence.map/filter/reduce are the same for-loop.",
            ha="center", fontsize=9.2, color="#444", style="italic")

    fig.tight_layout()
    out = os.path.join(HERE, "hof.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
