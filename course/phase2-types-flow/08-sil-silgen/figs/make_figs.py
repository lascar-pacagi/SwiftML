#!/usr/bin/env python3
"""Figures for 08-sil-silgen/explainer.qmd.

    .venv/bin/python phase2-types-flow/08-sil-silgen/figs/make_figs.py

Produces:
    figs/lowering.png — SILGen's core job, on a real program: the source, its AST (a
    tree), and the SIL control-flow graph 08's SILGen actually emits for it (a cond_br
    "diamond": entry -> then/else -> merge, with the block numbers SILGen assigns).
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
    ax.text(x, y, label, ha="center", va="center", fontsize=12, fontweight="bold", color=TEXT, zorder=4)


def blk(ax, x, y, lines, color, w=2.0, h=0.95):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.03,rounding_size=0.08",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y, "\n".join(lines), ha="center", va="center", fontsize=10.5, family="monospace", color=TEXT, zorder=4)


def line(ax, p0, p1, color=EDGE):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-", linewidth=1.3, color=color, zorder=1))


def arr(ax, p0, p1, color=EDGE, label=None, lx=0, ly=0, size=10):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=13, linewidth=1.5, color=color, zorder=2))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + lx, (p0[1] + p1[1]) / 2 + ly, label, ha="center", color=color,
                fontsize=size, fontweight="bold", zorder=5)


PROGRAM = [
    "func f(_ x: Int) {",
    "  if x > 3 {",
    "    print(1)",
    "  } else {",
    "    print(2)",
    "  }",
    "  print(3)",
    "}",
]


def node(ax, x, y, text, color, w, h=0.62, size=16.5):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                 boxstyle="round,pad=0.02,rounding_size=0.14", linewidth=1.4,
                 edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y, text, ha="center", va="center", fontsize=size, family="monospace",
            fontweight="bold", color=TEXT, zorder=4)


def block(ax, x, y, name, lines, w, color=BLK):
    h = 0.52 * (len(lines) + 1) + 0.24
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                 boxstyle="round,pad=0.03,rounding_size=0.08", linewidth=1.4,
                 edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h / 2 - 0.42
    ax.text(x - w / 2 + 0.18, ty, name, ha="left", va="center", fontsize=15.9,
            family="monospace", fontweight="bold", color=TEXT, zorder=4)
    for ln in lines:
        ty -= 0.52
        ax.text(x - w / 2 + 0.34, ty, ln, ha="left", va="center", fontsize=14.8,
                family="monospace", color=TEXT, zorder=4)
    return h


def make_lowering():
    fig, ax = plt.subplots(figsize=(16.0, 12.4))
    ax.set_xlim(-0.3, 16.1)
    ax.set_ylim(-0.45, 12.4)
    ax.axis("off")

    # ---- top: the program ----------------------------------------------------------
    ax.add_patch(FancyBboxPatch((0.4, 8.35), 5.6, 3.55, boxstyle="round,pad=0.03,rounding_size=0.1",
                 linewidth=1.4, edgecolor=EDGE, facecolor="#f6f8fa", zorder=1))
    ax.text(0.4, 12.15, "the program", ha="left", fontsize=17.7, fontweight="bold", color=TEXT)
    y = 11.55
    for ln in PROGRAM:
        ax.text(0.75, y, ln, ha="left", va="center", fontsize=17.7, family="monospace", color=TEXT)
        y -= 0.41
    ax.text(6.5, 11.35, "Parse and Sema turn it into a tree (bottom left).\n"
            "SILGen walks that tree and builds a graph (bottom right):\n"
            "one basic block per straight-line stretch, joined by branches.",
            ha="left", va="center", fontsize=17.1, color=TEXT, linespacing=1.5)

    # ---- bottom left: the AST ------------------------------------------------------
    ax.text(3.5, 7.55, "AST: a tree", ha="center", fontsize=18.9, fontweight="bold", color=TEXT)
    fn, iff, p3 = (3.5, 6.75), (2.2, 5.35), (5.3, 5.35)
    gt, th, el = (0.8, 3.85), (2.55, 3.85), (4.45, 3.85)
    vx, v3 = (0.35, 2.45), (1.25, 2.45)
    for a_, b_ in [(fn, iff), (fn, p3), (iff, gt), (iff, th), (iff, el), (gt, vx), (gt, v3)]:
        line(ax, a_, b_)
    node(ax, *fn, "func f", NODE, 1.9)
    node(ax, *iff, "if", NODE, 1.0)
    node(ax, *p3, "print(3)", LEAF, 1.9, size=15.3)
    node(ax, *gt, ">", NODE, 0.8)
    node(ax, *th, "print(1)", LEAF, 1.6, size=15.3)
    node(ax, *el, "print(2)", LEAF, 1.6, size=15.3)
    node(ax, *vx, "x", LEAF, 0.7)
    node(ax, *v3, "3", LEAF, 0.7)
    for (x, yy), lab in [(gt, "cond"), (th, "then"), (el, "else")]:
        ax.text(x, yy + 0.52, lab, ha="center", fontsize=14.8, style="italic", color="#5b6b7b")
    ax.text(3.5, 1.35, "nested: the `if` OWNS its branches,\nand nothing says what runs next",
            ha="center", va="center", fontsize=15.9, color=TEXT, style="italic", linespacing=1.4)

    # ---- the arrow -----------------------------------------------------------------
    arr(ax, (6.45, 4.6), (7.75, 4.6), EDGE)
    ax.text(7.1, 5.0, "SILGen", ha="center", fontsize=18.3, fontweight="bold", color=TEXT)

    # ---- bottom right: the CFG -----------------------------------------------------
    ax.text(11.9, 10.1, "SIL: a control-flow graph", ha="center", fontsize=18.9,
            fontweight="bold", color=TEXT)
    # the function header, as --emit-sil prints it: it is where %0 is DEFINED — the parameter
    ax.text(9.75, 9.45, r"sil @f(%0 : \$Int) -> \$() {", ha="left", va="center",
            fontsize=15.5, family="monospace", fontweight="bold", color=TEXT)
    ax.text(15.95, 9.45, "%0 is the parameter x", ha="right", va="center", fontsize=14.8,
            color="#5b6b7b", style="italic")
    b0 = (11.9, 7.05)
    h0 = block(ax, *b0, "bb0:", ["%1 = alloc_stack $Int", "store %0 to %1", "%3 = load %1",
                                  "%4 = integer_literal 3", "%5 = binop \">\" %3, %4",
                                  "cond_br %5, bb1, bb3"], 4.3)
    b1, b3 = (9.75, 3.35), (14.05, 3.35)
    h1 = block(ax, *b1, "bb1:  (then)", ["apply @print(1)", "br bb2"], 3.3)
    block(ax, *b3, "bb3:  (else)", ["apply @print(2)", "br bb2"], 3.3)
    b2 = (11.9, 0.75)
    h2 = block(ax, *b2, "bb2:  (merge)", ["apply @print(3)", "return"], 3.3)
    top1 = b1[1] + h1 / 2
    arr(ax, (b0[0] - 1.2, b0[1] - h0 / 2), (b1[0] + 0.3, top1), T, "true", lx=-0.6, ly=0.0,
        size=16.5)
    arr(ax, (b0[0] + 1.2, b0[1] - h0 / 2), (b3[0] - 0.3, top1), F, "false", lx=0.65, ly=0.0,
        size=16.5)
    arr(ax, (b1[0] + 0.5, b1[1] - h1 / 2), (b2[0] - 0.7, b2[1] + h2 / 2), EDGE)
    arr(ax, (b3[0] - 0.5, b3[1] - h1 / 2), (b2[0] + 0.7, b2[1] + h2 / 2), EDGE)
    ax.text(9.85, 0.75, "numbered in the order\nSILGen CREATES them:\nthe merge block exists\n"
            "before the else does", ha="right", va="center", fontsize=14.8, color="#5b6b7b",
            style="italic", linespacing=1.35)

    fig.tight_layout()
    out = os.path.join(HERE, "lowering.png")
    fig.savefig(out, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_lowering()
