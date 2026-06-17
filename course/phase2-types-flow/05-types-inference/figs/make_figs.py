#!/usr/bin/env python3
"""Figures for 05-types-inference/explainer.qmd.

    .venv/bin/python phase2-types-flow/05-types-inference/figs/make_figs.py

Produces:
    figs/bidir.png — the two modes of bidirectional checking on `1 + 2`:
      infer (synthesis) flows types UP; check(·, Double) pushes the expected type DOWN,
      which is what lets the integer literals coerce to Double.
"""
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


def flow(ax, p0, p1, color):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.6,
                                 color=color, zorder=2, connectionstyle="arc3,rad=0.25"))


def make_bidir():
    fig, ax = plt.subplots(figsize=(10.2, 5.0))
    ax.set_xlim(0, 11)
    ax.set_ylim(0, 5.2)
    ax.axis("off")

    # ---- left: infer (synthesis) ----
    p, a, b = (2.4, 3.4), (1.3, 1.6), (3.5, 1.6)
    tree_edges(ax, p, [a, b])
    node(ax, *p, "+", OP)
    node(ax, *a, "1", LIT)
    node(ax, *b, "2", LIT)
    ax.text(a[0], a[1] - 0.6, "Int", ha="center", color=UP, fontsize=11, fontweight="bold")
    ax.text(b[0], b[1] - 0.6, "Int", ha="center", color=UP, fontsize=11, fontweight="bold")
    ax.text(p[0] + 0.95, p[1], "Int", ha="left", va="center", color=UP, fontsize=11, fontweight="bold")
    flow(ax, (a[0] + 0.3, a[1] + 0.3), (p[0] - 0.35, p[1] - 0.35), UP)
    flow(ax, (b[0] - 0.3, b[1] + 0.3), (p[0] + 0.35, p[1] - 0.35), UP)
    ax.text(2.4, 4.55, "infer  —  types flow UP", ha="center", fontsize=12.5, fontweight="bold", color=TEXT)
    ax.text(2.4, 0.5, "no expectation: 1 + 2 : Int", ha="center", fontsize=9.5, color=UP, fontstyle="italic")

    # divider
    ax.plot([5.5, 5.5], [0.3, 4.9], color="#cccccc", linewidth=1.2, linestyle=(0, (4, 4)))

    # ---- right: check against Double ----
    P, A, B = (8.4, 3.4), (7.3, 1.6), (9.5, 1.6)
    tree_edges(ax, P, [A, B])
    node(ax, *P, "+", OP)
    node(ax, *A, "1", LIT)
    node(ax, *B, "2", LIT)
    ax.text(P[0] + 0.55, P[1] + 0.35, "⇐ Double", ha="left", va="center", color=DOWN, fontsize=11, fontweight="bold")
    ax.text(A[0], A[1] - 0.55, "⇐ Double", ha="center", color=DOWN, fontsize=10, fontweight="bold")
    ax.text(B[0], B[1] - 0.55, "⇐ Double", ha="center", color=DOWN, fontsize=10, fontweight="bold")
    ax.text(A[0], A[1] - 0.95, "✓ Int literal", ha="center", color=UP, fontsize=8.5, fontstyle="italic")
    ax.text(B[0], B[1] - 0.95, "✓ Int literal", ha="center", color=UP, fontsize=8.5, fontstyle="italic")
    flow(ax, (P[0] - 0.35, P[1] - 0.35), (A[0] + 0.3, A[1] + 0.35), DOWN)
    flow(ax, (P[0] + 0.35, P[1] - 0.35), (B[0] - 0.3, B[1] + 0.35), DOWN)
    ax.text(8.4, 4.55, "check( · , Double)  —  expected type flows DOWN", ha="center", fontsize=12.5,
            fontweight="bold", color=TEXT)
    ax.text(8.4, 0.5, "let d: Double = 1 + 2   (literals coerce)", ha="center", fontsize=9.5,
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
