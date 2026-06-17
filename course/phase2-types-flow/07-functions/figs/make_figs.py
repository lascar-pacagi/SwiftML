#!/usr/bin/env python3
"""Figures for 07-functions/explainer.qmd.

    .venv/bin/python phase2-types-flow/07-functions/figs/make_figs.py

Produces:
    figs/twopass.png — why sema makes TWO passes: collect every function's signature
    first, then check the bodies. That order is what lets a function call itself
    (recursion) and lets a call appear before the function's declaration (forward ref).
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = "#eef2f7"
TAB = "#fff3d6"
CHK = "#dceede"
EDGE = "#5b6b7b"
TEXT = "#1b2733"
HL = "#b5651d"


def box(ax, x, y, w, h, title, lines, color):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                 boxstyle="round,pad=0.04,rounding_size=0.06", linewidth=1.3,
                 edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y + h / 2 - 0.3, title, ha="center", va="center", fontsize=11,
            fontweight="bold", color=TEXT, zorder=4)
    ax.text(x, y - 0.18, "\n".join(lines), ha="center", va="center", fontsize=9.5,
            family="monospace", color=TEXT, zorder=4)


def arrow(ax, p0, p1, label=None, color=EDGE, ly=0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=15, linewidth=1.6,
                 color=color, zorder=2))
    if label:
        ax.text((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + ly, label, ha="center",
                va="center", fontsize=9, color=color, fontstyle="italic", zorder=5)


def make_twopass():
    fig, ax = plt.subplots(figsize=(10.2, 5.0))
    ax.set_xlim(0, 11)
    ax.set_ylim(0, 5.2)
    ax.axis("off")

    box(ax, 1.9, 2.6, 3.3, 3.0, "source items",
        ["func fib(_ n: Int)", "  -> Int {", "   … fib(n-1) …", "}", "", "print(fib(10))"], SRC)
    box(ax, 5.5, 3.4, 3.0, 1.6, "Pass 1: signatures",
        ["fib : (Int) -> Int"], TAB)
    box(ax, 9.1, 2.6, 3.2, 3.0, "Pass 2: check bodies",
        ["check fib's body", "  fib(n-1) ✓", "", "check top level", "  print(fib(10)) ✓"], CHK)

    arrow(ax, (3.6, 3.2), (4.0, 3.4), "scan decls", ly=0.3)
    arrow(ax, (7.0, 3.2), (7.5, 2.9), "resolve calls", ly=0.3)
    # the two payoffs
    ax.annotate("recursion: fib calls fib", xy=(9.1, 3.55), xytext=(6.0, 1.0),
                fontsize=9, color=HL, fontweight="bold",
                arrowprops=dict(arrowstyle="-|>", color=HL, lw=1.3))
    ax.annotate("forward ref: print before func", xy=(9.0, 1.65), xytext=(5.4, 0.4),
                fontsize=9, color=HL, fontweight="bold",
                arrowprops=dict(arrowstyle="-|>", color=HL, lw=1.3))

    ax.set_title("Two passes: collect every signature first, then check bodies\n"
                 "(so a function can call itself, and a call can precede its declaration)",
                 fontsize=12.5, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "twopass.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_twopass()
