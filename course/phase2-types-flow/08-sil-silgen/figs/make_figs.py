#!/usr/bin/env python3
"""Figures for 08-sil-silgen/explainer.qmd.

    .venv/bin/python phase2-types-flow/08-sil-silgen/figs/make_figs.py

Produces:
    figs/lowering.png — SILGen's core job: an `if`/`else` AST (a tree) becomes a SIL
    control-flow graph (a cond_br "diamond": entry -> then/else -> merge).
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Circle

HERE = os.path.dirname(os.path.abspath(__file__))
NODE = "#fff3d6"
LEAF = "#dceede"
BLK = "#eef2f7"
EDGE = "#5b6b7b"
TEXT = "#1b2733"
T = "#2f6f4f"
F = "#b5651d"


def circle(ax, x, y, label, color, r=0.42):
    ax.add_patch(Circle((x, y), r, facecolor=color, edgecolor=EDGE, linewidth=1.3, zorder=3))
    ax.text(x, y, label, ha="center", va="center", fontsize=11, fontweight="bold", color=TEXT, zorder=4)


def blk(ax, x, y, lines, color, w=2.0, h=0.95):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.03,rounding_size=0.08",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y, "\n".join(lines), ha="center", va="center", fontsize=9, family="monospace", color=TEXT, zorder=4)


def line(ax, p0, p1, color=EDGE):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-", linewidth=1.3, color=color, zorder=1))


def arr(ax, p0, p1, color=EDGE, label=None, lx=0, ly=0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=13, linewidth=1.5, color=color, zorder=2))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + lx, (p0[1] + p1[1]) / 2 + ly, label, ha="center", color=color,
                fontsize=9, fontweight="bold", zorder=5)


def make_lowering():
    fig, ax = plt.subplots(figsize=(10.6, 5.6))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 6)
    ax.axis("off")

    # ---- left: the AST (a tree) ----
    ax.text(2.4, 5.6, "AST: a tree", ha="center", fontsize=12, fontweight="bold", color=TEXT)
    iff = (2.4, 4.4)
    c, th, el = (1.0, 2.9), (2.4, 2.9), (3.8, 2.9)
    for k in (c, th, el):
        line(ax, iff, k)
    circle(ax, *iff, "if", NODE)
    circle(ax, *c, "c", LEAF)
    circle(ax, *th, "A", LEAF)
    circle(ax, *el, "B", LEAF)
    ax.text(c[0], c[1] - 0.65, "cond", ha="center", fontsize=8, color=TEXT)
    ax.text(th[0], th[1] - 0.65, "then", ha="center", fontsize=8, color=TEXT)
    ax.text(el[0], el[1] - 0.65, "else", ha="center", fontsize=8, color=TEXT)

    # ---- middle arrow ----
    arr(ax, (4.6, 3.2), (5.7, 3.2), EDGE)
    ax.text(5.15, 3.55, "SILGen", ha="center", fontsize=10.5, fontweight="bold", color=TEXT)

    # ---- right: the SIL CFG (a graph) ----
    ax.text(8.9, 5.6, "SIL: a control-flow graph", ha="center", fontsize=12, fontweight="bold", color=TEXT)
    entry = (8.9, 4.6)
    then_b, else_b = (7.5, 3.0), (10.3, 3.0)
    merge = (8.9, 1.4)
    blk(ax, *entry, ["bb0:", "cond_br c"], BLK)
    blk(ax, *then_b, ["bb1:", "A", "br bb3"], BLK)
    blk(ax, *else_b, ["bb2:", "B", "br bb3"], BLK, h=1.1)
    blk(ax, *merge, ["bb3:", "…"], BLK)
    arr(ax, (entry[0] - 0.5, entry[1] - 0.45), (then_b[0] + 0.3, then_b[1] + 0.55), T, "true", lx=-0.45)
    arr(ax, (entry[0] + 0.5, entry[1] - 0.45), (else_b[0] - 0.3, else_b[1] + 0.55), F, "false", lx=0.5)
    arr(ax, (then_b[0] + 0.3, then_b[1] - 0.5), (merge[0] - 0.5, merge[1] + 0.45), EDGE)
    arr(ax, (else_b[0] - 0.3, else_b[1] - 0.55), (merge[0] + 0.5, merge[1] + 0.45), EDGE)

    ax.set_title("SILGen lowers the AST tree into a SIL control-flow graph (basic blocks + branches)",
                 fontsize=12.5, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "lowering.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_lowering()
