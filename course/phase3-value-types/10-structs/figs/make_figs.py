#!/usr/bin/env python3
"""Figures for 10-structs/explainer.qmd.

    .venv/bin/python phase3-value-types/10-structs/figs/make_figs.py

Produces:
    figs/value_semantics.png — why a struct is a *value type*: `var q = p` copies the whole
    aggregate into q's own slot, so `q.x = 99` mutates only q; p is untouched.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
BOX = "#eef2f7"
SAME = "#dceede"
CHG = "#ffe0c2"


def struct_box(ax, x, y, name, fields, hot=None):
    w, cell = 2.2, 0.62
    h = cell * len(fields) + 0.5
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.02,rounding_size=0.06",
                 linewidth=1.4, edgecolor=EDGE, facecolor="white", zorder=2))
    ax.text(x, y + h / 2 - 0.26, name, ha="center", va="center", fontsize=11, fontweight="bold", color=TEXT, zorder=4)
    top = y + h / 2 - 0.5
    for i, (fn, fv) in enumerate(fields):
        cy = top - i * cell - cell / 2
        fc = CHG if hot == i else SAME
        ax.add_patch(Rectangle((x - w / 2 + 0.12, cy - cell / 2 + 0.05), w - 0.24, cell - 0.1,
                     facecolor=fc, edgecolor=EDGE, linewidth=1.0, zorder=3))
        ax.text(x, cy, f"{fn} = {fv}", ha="center", va="center", fontsize=10.5, family="monospace", color=TEXT, zorder=4)


def make_value_semantics():
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(10.8, 4.6))
    for ax in (a1, a2):
        ax.set_xlim(0, 6)
        ax.set_ylim(0, 5)
        ax.axis("off")

    # left: var q = p  (the copy)
    a1.set_title("var q = p   →   p is COPIED into q's own slot", fontsize=11.5, color=TEXT, pad=6)
    struct_box(a1, 1.7, 2.5, "p (slot)", [("x", 1), ("y", 2)])
    struct_box(a1, 4.3, 2.5, "q (slot)", [("x", 1), ("y", 2)])
    a1.add_patch(FancyArrowPatch((2.85, 2.5), (3.15, 2.5), arrowstyle="-|>", mutation_scale=16, linewidth=1.8, color="#b5651d", zorder=5))
    a1.text(3.0, 3.15, "copy", ha="center", fontsize=10, color="#b5651d", fontweight="bold")

    # right: q.x = 99  (only q changes)
    a2.set_title("q.x = 99   →   only q changes; p is untouched", fontsize=11.5, color=TEXT, pad=6)
    struct_box(a2, 1.7, 2.5, "p (slot)", [("x", 1), ("y", 2)])
    struct_box(a2, 4.3, 2.5, "q (slot)", [("x", 99), ("y", 2)], hot=0)
    a2.text(1.7, 0.5, "print(p.x) → 1", ha="center", fontsize=10, color="#2f6f4f", family="monospace")
    a2.text(4.3, 0.5, "print(q.x) → 99", ha="center", fontsize=10, color="#b5651d", family="monospace")

    fig.suptitle("Value semantics: a struct is copied on assignment, so each variable owns its data",
                 fontsize=13, color=TEXT, y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.93])
    out = os.path.join(HERE, "value_semantics.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_value_semantics()
