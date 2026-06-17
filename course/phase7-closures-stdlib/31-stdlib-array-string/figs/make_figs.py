#!/usr/bin/env python3
"""figs/cow.png — copy-on-write value semantics for Array. `var b = a` SHARES the buffer
(refcount 2); the first mutation of either binding makes it unique (copies iff refcount > 1),
so `a` never sees `b`'s write. This is what makes a reference-backed type behave like a value."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"
VAR = "#eef2f7"; BUF = "#dceede"; BUF2 = "#fde8d6"; HDR = "#fff3d6"


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


def arr(ax, p0, p1, color="#b5651d", label=None, dx=0, dy=0.12):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.7,
                 color=color, zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center",
                fontsize=8.2, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(12.2, 6.4))
    ax.set_xlim(0, 13); ax.set_ylim(0, 7); ax.axis("off")
    ax.text(6.5, 6.75, "Array copy-on-write: share cheaply, copy only on a mutation of a shared buffer",
            ha="center", fontsize=11.5, fontweight="bold", color=TEXT)

    # --- stage 1: var a = [1,2,3] ---
    ax.text(2.0, 6.1, "var a = [1,2,3]", ha="center", fontsize=9, family="monospace", color="#444")
    box(ax, 0.5, 4.7, 1.5, 0.7, ["a"], VAR)
    box(ax, 2.4, 4.3, 3.0, 1.3, ["count 3  cap 4", "[1, 2, 3, _]"], BUF, title="buffer  refcount 1", fs=8.4)
    arr(ax, (2.0, 5.05), (2.4, 5.05))

    # --- stage 2: var b = a  (SHARE) ---
    ax.text(8.7, 6.1, "var b = a   // retain: refcount 1 -> 2", ha="center", fontsize=9, family="monospace", color="#444")
    box(ax, 6.6, 5.0, 1.4, 0.7, ["a"], VAR)
    box(ax, 6.6, 4.0, 1.4, 0.7, ["b"], VAR)
    box(ax, 8.6, 4.3, 3.4, 1.3, ["count 3  cap 4", "[1, 2, 3, _]"], BUF, title="buffer  refcount 2  (shared)", fs=8.4)
    arr(ax, (8.0, 5.35), (8.6, 5.15))
    arr(ax, (8.0, 4.35), (8.6, 4.75))

    # --- stage 3: b.append(4) -> make_unique copies ---
    ax.text(3.2, 3.05, "b.append(4)  ->  make_unique sees refcount 2  ->  COPY", ha="center",
            fontsize=9, family="monospace", color="#a14a00")
    box(ax, 0.5, 1.5, 1.3, 0.7, ["a"], VAR)
    box(ax, 0.5, 0.5, 1.3, 0.7, ["b"], VAR)
    box(ax, 2.3, 1.35, 3.0, 1.05, ["count 3  cap 4", "[1, 2, 3, _]"], BUF, title="original  refcount 1", fs=8.0)
    box(ax, 6.2, 0.35, 3.0, 1.15, ["count 4  cap 4", "[1, 2, 3, 4]"], BUF2, title="b's fresh copy  refcount 1", fs=8.0)
    arr(ax, (1.8, 1.85), (2.3, 1.85))
    arr(ax, (1.8, 0.85), (6.2, 0.9), label="copied & mutated", dx=0.4, dy=0.16)

    ax.text(10.8, 1.5, "a still sees\n[1, 2, 3]\n\nvalue semantics\nfrom a reference\n+ one refcount check",
            ha="center", va="center", fontsize=8.8, color="#2a6", fontweight="bold")

    fig.tight_layout()
    out = os.path.join(HERE, "cow.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
