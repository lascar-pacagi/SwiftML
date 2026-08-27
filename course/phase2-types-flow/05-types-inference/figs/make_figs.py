#!/usr/bin/env python3
"""Figures for 05-types-inference/explainer.qmd.

    .venv/bin/python phase2-types-flow/05-types-inference/figs/make_figs.py

Produces:
    figs/bidir.png — the two modes of bidirectional checking on `1 + 2`:
      infer (synthesis) flows types UP; check(·, Double) pushes the expected type DOWN,
      which is what lets the integer literals coerce to Double.
"""
import math
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
OP = "#fff3d6"
LIT = "#dceede"
EDGE = "#5b6b7b"
TEXT = "#1b2733"
UP = "#2f6f4f"   # inferred (synthesised) types
DOWN = "#b5651d"  # expected (pushed-down) types


def node(ax, x, y, label, color, r=0.36):
    ax.add_patch(plt.Circle((x, y), r, facecolor=color, edgecolor=EDGE, linewidth=1.3, zorder=3))
    ax.text(x, y, label, ha="center", va="center", fontsize=14, fontweight="bold", color=TEXT, zorder=4)


def tree_edges(ax, root, kids):
    for k in kids:
        ax.add_patch(FancyArrowPatch(root, k, arrowstyle="-", linewidth=1.3, color=EDGE, zorder=1))


def flow_along(ax, src, dst, color, r=0.36, gap=0.12, side=1, offset=0.20):
    """A straight arrow running ALONGSIDE the src->dst tree edge.

    Endpoints sit on the two circles' boundaries (not their centres, which is what made
    the arrows appear to float), and the whole arrow is shifted perpendicular to the edge
    so it runs parallel to it instead of across it."""
    dx, dy = dst[0] - src[0], dst[1] - src[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    nx, ny = -uy * offset * side, ux * offset * side
    p0 = (src[0] + ux * (r + gap) + nx, src[1] + uy * (r + gap) + ny)
    p1 = (dst[0] - ux * (r + gap) + nx, dst[1] - uy * (r + gap) + ny)
    ax.add_patch(
        FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=13, linewidth=1.7,
                        color=color, zorder=2))


def make_bidir():
    fig, ax = plt.subplots(figsize=(11.4, 5.4))
    ax.set_xlim(0, 13.0)
    ax.set_ylim(0, 5.4)
    ax.axis("off")

    # ---- left: infer (synthesis) — each child's type travels UP to the parent ----
    p, a, b = (2.6, 3.3), (1.5, 1.7), (3.7, 1.7)
    tree_edges(ax, p, [a, b])
    node(ax, *p, "+", OP)
    node(ax, *a, "1", LIT)
    node(ax, *b, "2", LIT)
    ax.text(a[0], a[1] - 0.62, "Int", ha="center", color=UP, fontsize=11, fontweight="bold")
    ax.text(b[0], b[1] - 0.62, "Int", ha="center", color=UP, fontsize=11, fontweight="bold")
    ax.text(p[0] + 0.62, p[1] + 0.16, "Int", ha="left", va="center", color=UP, fontsize=11,
            fontweight="bold")
    flow_along(ax, a, p, UP, side=1)
    flow_along(ax, b, p, UP, side=-1)
    ax.text(2.6, 4.75, "infer  —  types flow UP", ha="center", fontsize=12.5, fontweight="bold",
            color=TEXT)
    ax.text(2.6, 0.42, "no expectation:  1 + 2 : Int", ha="center", fontsize=9.5, color=UP,
            fontstyle="italic")

    # divider
    ax.plot([6.1, 6.1], [0.3, 5.0], color="#cccccc", linewidth=1.2, linestyle=(0, (4, 4)))

    # ---- right: check against Double — the expectation travels DOWN to the children ----
    P, A, B = (9.2, 3.3), (8.1, 1.7), (10.3, 1.7)
    tree_edges(ax, P, [A, B])
    node(ax, *P, "+", OP)
    node(ax, *A, "1", LIT)
    node(ax, *B, "2", LIT)
    ax.text(P[0] + 0.62, P[1] + 0.16, "\u21d0 Double", ha="left", va="center", color=DOWN,
            fontsize=11, fontweight="bold")
    ax.text(A[0], A[1] - 0.62, "\u21d0 Double", ha="center", color=DOWN, fontsize=10,
            fontweight="bold")
    ax.text(B[0], B[1] - 0.62, "\u21d0 Double", ha="center", color=DOWN, fontsize=10,
            fontweight="bold")
    ax.text(A[0], A[1] - 1.02, "\u2713 Int literal", ha="center", color=UP, fontsize=8.5,
            fontstyle="italic")
    ax.text(B[0], B[1] - 1.02, "\u2713 Int literal", ha="center", color=UP, fontsize=8.5,
            fontstyle="italic")
    flow_along(ax, P, A, DOWN, side=-1)
    flow_along(ax, P, B, DOWN, side=1)
    ax.text(9.2, 4.75, "check( \u00b7 , Double)  \u2014  types flow DOWN", ha="center",
            fontsize=12.5, fontweight="bold", color=TEXT)
    ax.text(9.2, 0.42, "let d: Double = 1 + 2   (literals coerce)", ha="center", fontsize=9.5,
            color=DOWN, fontstyle="italic")

    ax.set_title("Bidirectional type checking: synthesise upward, check downward",
                 fontsize=13, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "bidir.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_bidir()
