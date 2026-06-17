#!/usr/bin/env python3
"""Generate the figures embedded in 02-parser/explainer.qmd.

Run from the course/ root (the Makefile's `figs` target does this for you):

    .venv/bin/python phase1-minimal/02-parser/figs/make_figs.py

Produces:
    figs/pratt.png  — the Pratt parse / AST of `1 + 2 * 3`: `*` (bp 20) binds tighter
                      than `+` (bp 10), so it forms its subtree first → (+ 1 (* 2 3)).

Real figure, from a real script (per CLAUDE.md: diagrams come from figs/, not stock art).
"""
import os
import matplotlib

matplotlib.use("Agg")  # headless: write a PNG, never open a window
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))

OP = "#fff3d6"  # operator nodes
LIT = "#dceede"  # literal/leaf nodes
EDGE = "#5b6b7b"
TEXT = "#1b2733"


def node(ax, x, y, label, color, sub=None, r=0.42):
    ax.add_patch(
        plt.Circle((x, y), r, facecolor=color, edgecolor=EDGE, linewidth=1.3, zorder=3)
    )
    ax.text(x, y, label, ha="center", va="center", fontsize=15, fontweight="bold",
            color=TEXT, zorder=4)
    if sub:
        ax.text(x + r + 0.12, y + r - 0.05, sub, ha="left", va="center", fontsize=9,
                fontstyle="italic", color=TEXT, zorder=4)


def edge(ax, p0, p1):
    ax.add_patch(
        FancyArrowPatch(p0, p1, arrowstyle="-", linewidth=1.4, color=EDGE, zorder=1)
    )


def make_pratt():
    fig, ax = plt.subplots(figsize=(7.2, 5.2))
    ax.set_xlim(0, 8)
    ax.set_ylim(0, 6)
    ax.set_aspect("equal")
    ax.axis("off")

    # positions
    plus = (3.0, 4.7)
    one = (1.4, 3.0)
    star = (4.6, 3.0)
    two = (3.6, 1.3)
    three = (5.6, 1.3)

    # edges first (under the nodes)
    edge(ax, plus, one)
    edge(ax, plus, star)
    edge(ax, star, two)
    edge(ax, star, three)

    # nodes
    node(ax, *plus, "+", OP, sub="bp 10")
    node(ax, *one, "1", LIT)
    node(ax, *star, "*", OP, sub="bp 20")
    node(ax, *two, "2", LIT)
    node(ax, *three, "3", LIT)

    # the "* binds first" annotation: a soft box around the * subtree
    ax.add_patch(
        FancyBboxPatch(
            (2.9, 0.6), 3.4, 3.0,
            boxstyle="round,pad=0.02,rounding_size=0.12",
            linewidth=1.1, linestyle=(0, (4, 3)),
            edgecolor="#c08a2a", facecolor="none", zorder=0,
        )
    )
    ax.text(6.45, 3.35, "formed first\n(tighter bp)", ha="left", va="center",
            fontsize=9, color="#9a6b1f", fontstyle="italic")

    ax.set_title("Pratt parse of  1 + 2 * 3   →   (+ 1 (* 2 3))",
                 fontsize=13, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "pratt.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_pratt()
