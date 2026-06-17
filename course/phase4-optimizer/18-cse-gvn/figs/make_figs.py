#!/usr/bin/env python3
"""Figures for 18-cse-gvn/explainer.qmd.

    .venv/bin/python phase4-optimizer/18-cse-gvn/figs/make_figs.py

Produces:
    figs/gvn.png — GVN: two instructions with the same value KEY compute the same value, so the
    second is redundant and its uses redirect to the first. Correct only where the first
    DOMINATES the second (the scoped table).
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
BOX = "#eef2f7"
HL = "#dceede"
DEAD = "#f3d6d6"


def code(ax, x, y, lines, color, w=4.4, h=2.0):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.04,rounding_size=0.06",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h / 2 - 0.36
    for ln, dead in lines:
        ax.text(x, ty, ln, ha="center", va="center", fontsize=9.0, family="monospace",
                color=("#c33" if dead else TEXT), zorder=4,
                fontstyle=("italic" if dead else "normal"))
        ty -= 0.4


def make():
    fig, ax = plt.subplots(figsize=(11.0, 5.2))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 5.4)
    ax.axis("off")

    code(ax, 3.0, 3.4, [
        ('%1 = binop "*" x, x', False),
        ('%2 = binop "*" x, x', False),
        ('%3 = binop "+" %1, %2', False),
    ], BOX)
    ax.text(3.0, 1.7, "two identical computations\n(same value key)", ha="center", fontsize=9, color="#777")

    ax.add_patch(FancyArrowPatch((5.4, 3.4), (6.6, 3.4), arrowstyle="-|>", mutation_scale=16, linewidth=1.8, color="#b5651d", zorder=2))
    ax.text(6.0, 3.85, "GVN", ha="center", fontsize=10.5, fontweight="bold", color="#b5651d")

    code(ax, 9.0, 3.4, [
        ('%1 = binop "*" x, x', False),
        ('(%2 removed — same as %1)', True),
        ('%3 = binop "+" %1, %1', False),
    ], HL)
    ax.text(9.0, 1.7, "computed once; %2's uses\nredirect to %1", ha="center", fontsize=9, color="#2f6f4f")

    fig.suptitle("GVN / CSE: equal value keys ⇒ equal values — keep one, redirect the rest\n"
                 "(correct only where the surviving definition DOMINATES the use — a dominance-scoped table)",
                 fontsize=12, color=TEXT, y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.86])
    out = os.path.join(HERE, "gvn.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
