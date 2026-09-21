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
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

HERE = os.path.dirname(os.path.abspath(__file__))
OP = "#fff3d6"
LIT = "#dceede"
EDGE = "#5b6b7b"
TEXT = "#1b2733"
UP = "#2f6f4f"   # inferred (synthesised) types
DOWN = "#b5651d"  # expected (pushed-down) types
STEP = "#b4453a"  # the step badges


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


def badge(ax, x, y, n, r=0.36, dx=-1.0, dy=1.0):
    """The step number, in its own badge, clear of the node and its type label."""
    bx, by = x + dx * (r + 0.20), y + dy * (r + 0.20)
    ax.add_patch(plt.Circle((bx, by), 0.20, facecolor=STEP, edgecolor="none", zorder=5))
    ax.text(bx, by, str(n), ha="center", va="center", fontsize=10.5, fontweight="bold",
            color="white", zorder=6)


def outcome(ax, x, y, w, h, heading, lines, accent):
    """What the walk hands back: the typed nodes, with the type written ON each one."""
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.03,rounding_size=0.1",
                                linewidth=1.2, edgecolor="#c9d3dc", facecolor="#f3f6f8",
                                zorder=2))
    ax.text(x + w / 2, y + h - 0.30, heading, ha="center", va="center", fontsize=11,
            fontweight="bold", color=TEXT, zorder=3)
    ly = y + h - 0.78
    for text, colour in lines:
        ax.text(x + 0.30, ly, text, ha="left", va="center", fontsize=10.5,
                family="monospace", color=colour, zorder=3)
        ly -= 0.42
    ax.plot([x + 0.18, x + w - 0.18], [y + 0.46, y + 0.46], color="#d8e0e6", linewidth=1)
    return y + 0.24


def make_bidir():
    fig, ax = plt.subplots(figsize=(12.6, 7.6))
    ax.set_xlim(0, 13.4)
    ax.set_ylim(-0.1, 7.6)
    ax.axis("off")

    # ---- left: infer (synthesis) — each child's type travels UP to the parent ----
    p, a, b = (3.2, 5.5), (2.0, 3.9), (4.4, 3.9)
    tree_edges(ax, p, [a, b])
    node(ax, *p, "+", OP)
    node(ax, *a, "1", LIT)
    node(ax, *b, "2", LIT)
    # the walk reaches the operands FIRST and has nothing to say about them until it
    # has read them: 1, then 2, then the operator that adds their types up
    badge(ax, *a, 1, dx=-1.0, dy=0.9)
    badge(ax, *b, 2, dx=1.0, dy=0.9)
    badge(ax, *p, 3, dx=-1.0, dy=1.0)
    ax.text(a[0], a[1] - 0.62, "Int", ha="center", color=UP, fontsize=11, fontweight="bold")
    ax.text(b[0], b[1] - 0.62, "Int", ha="center", color=UP, fontsize=11, fontweight="bold")
    ax.text(p[0] + 0.62, p[1] + 0.16, "Int", ha="left", va="center", color=UP, fontsize=11,
            fontweight="bold")
    flow_along(ax, a, p, UP, side=1)
    flow_along(ax, b, p, UP, side=-1)
    ax.text(3.2, 7.0, "infer  \u2014  types flow UP", ha="center", fontsize=13, fontweight="bold",
            color=TEXT)
    ax.text(3.2, 6.58, "let n = 1 + 2      (nothing says what to want)", ha="center",
            fontsize=10, color=UP, fontstyle="italic")

    # divider
    ax.plot([6.7, 6.7], [0.15, 7.1], color="#cccccc", linewidth=1.2, linestyle=(0, (4, 4)))

    # ---- right: check against Double — the expectation travels DOWN to the children ----
    P, A, B = (10.2, 5.5), (9.0, 3.9), (11.4, 3.9)
    tree_edges(ax, P, [A, B])
    node(ax, *P, "+", OP)
    node(ax, *A, "1", LIT)
    node(ax, *B, "2", LIT)
    # and here it starts at the ROOT, because the root is where the expectation arrives
    badge(ax, *P, 1, dx=-1.0, dy=1.0)
    badge(ax, *A, 2, dx=-1.0, dy=0.9)
    badge(ax, *B, 3, dx=1.0, dy=0.9)
    ax.text(P[0] + 0.62, P[1] + 0.16, "\u21d0 Double", ha="left", va="center", color=DOWN,
            fontsize=11, fontweight="bold")
    ax.text(A[0], A[1] - 0.62, "\u21d0 Double", ha="center", color=DOWN, fontsize=10,
            fontweight="bold")
    ax.text(B[0], B[1] - 0.62, "\u21d0 Double", ha="center", color=DOWN, fontsize=10,
            fontweight="bold")
    flow_along(ax, P, A, DOWN, side=-1)
    flow_along(ax, P, B, DOWN, side=1)
    ax.text(10.2, 7.0, "check( \u00b7 , Double)  \u2014  types flow DOWN", ha="center",
            fontsize=13, fontweight="bold", color=TEXT)
    ax.text(10.2, 6.58, "let d: Double = 1 + 2      (the annotation says)", ha="center",
            fontsize=10, color=DOWN, fontstyle="italic")

    # ---- what each walk HANDS BACK: the same source, two different typed trees -------
    foot = outcome(ax, 0.55, 0.30, 5.3, 2.6, "the typed node it hands back",
                   [("Binary(+)   : Int", UP),
                    ("  Int_lit 1 : Int", UP),
                    ("  Int_lit 2 : Int", UP)], UP)
    ax.text(0.55 + 5.3 / 2, foot, "an Int literal read with no expectation is an Int",
            ha="center", va="center", fontsize=9.5, color=TEXT, fontstyle="italic", zorder=3)

    foot = outcome(ax, 7.55, 0.30, 5.3, 2.6, "the typed node it hands back",
                   [("Binary(+)   : Double", DOWN),
                    ("  Int_lit 1 : Double", DOWN),
                    ("  Int_lit 2 : Double", DOWN)], DOWN)
    ax.text(7.55 + 5.3 / 2, foot, "the flex is WRITTEN INTO the operand, not just allowed",
            ha="center", va="center", fontsize=9.5, color=TEXT, fontstyle="italic", zorder=3)

    ax.set_title(
        "Bidirectional type checking: same source, two walks, two typed trees",
        fontsize=13.5, color=TEXT, pad=10)
    fig.tight_layout()
    out = os.path.join(HERE, "bidir.png")
    fig.savefig(out, dpi=165, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_bidir()
