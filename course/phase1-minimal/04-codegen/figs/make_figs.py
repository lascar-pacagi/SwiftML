#!/usr/bin/env python3
"""Generate the figures embedded in 04-codegen/explainer.qmd.

Run from the course/ root (the Makefile's `figs` target does this for you):

    .venv/bin/python phase1-minimal/04-codegen/figs/make_figs.py

Produces:
    figs/lowering.png  — AST → LLVM IR for `1 + 2 * 3`: each node, in post-order,
                         emits instructions and returns a result operand (a literal
                         or a `%tN` register).

Real figure, from a real script (per CLAUDE.md: diagrams come from figs/, not stock art).
"""
import os
import matplotlib

matplotlib.use("Agg")  # headless: write a PNG, never open a window
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))

OP = "#fff3d6"   # operator nodes
LIT = "#dceede"  # literal/leaf nodes
CODE = "#eef2f7"  # the IR panel
EDGE = "#5b6b7b"
TEXT = "#1b2733"
REG = "#2f6f4f"  # returned-operand chips


def node(ax, x, y, label, color, ret, r=0.40):
    ax.add_patch(plt.Circle((x, y), r, facecolor=color, edgecolor=EDGE, linewidth=1.3, zorder=3))
    ax.text(x, y, label, ha="center", va="center", fontsize=14, fontweight="bold",
            color=TEXT, zorder=4)
    # the operand this node "returns"
    ax.text(x, y - r - 0.28, ret, ha="center", va="center", fontsize=10.5,
            color=REG, family="monospace", fontweight="bold", zorder=4)


def edge(ax, p0, p1):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-", linewidth=1.4, color=EDGE, zorder=1))


def make_lowering():
    fig, ax = plt.subplots(figsize=(9.4, 5.0))
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 6)
    ax.axis("off")

    plus = (2.5, 4.5)
    one = (1.1, 2.9)
    star = (3.9, 2.9)
    two = (3.0, 1.2)
    three = (4.8, 1.2)

    edge(ax, plus, one)
    edge(ax, plus, star)
    edge(ax, star, two)
    edge(ax, star, three)

    node(ax, *plus, "+", OP, "-> %t2")
    node(ax, *one, "1", LIT, "-> 1")
    node(ax, *star, "*", OP, "-> %t1")
    node(ax, *two, "2", LIT, "-> 2")
    node(ax, *three, "3", LIT, "-> 3")

    ax.text(2.5, 5.45, "AST of  1 + 2 * 3", ha="center", va="center", fontsize=12,
            fontweight="bold", color=TEXT)
    ax.text(2.5, 0.35, "green = the operand each node returns", ha="center", va="center",
            fontsize=9, color=REG, fontstyle="italic")

    # the IR panel (right), filled in post-order
    px, py, pw, ph = 6.0, 1.0, 3.7, 3.7
    ax.add_patch(FancyBboxPatch((px, py), pw, ph, boxstyle="round,pad=0.03,rounding_size=0.1",
                                linewidth=1.2, edgecolor=EDGE, facecolor=CODE, zorder=2))
    ax.text(px + pw / 2, py + ph - 0.32, "emitted IR  (post-order)", ha="center", va="center",
            fontsize=10.5, fontweight="bold", color=TEXT, zorder=3)
    lines = [
        ("visit 2, 3   ->  literals, no IR", TEXT),
        ("%t1 = mul i64 2, 3", REG),
        ("visit 1      ->  literal, no IR", TEXT),
        ("%t2 = add i64 1, %t1", REG),
        ("call printf(.., i64 %t2)", REG),
    ]
    y = py + ph - 0.95
    for text, color in lines:
        ax.text(px + 0.22, y, text, ha="left", va="center", fontsize=10,
                family="monospace", color=color, zorder=3)
        y -= 0.55

    ax.set_title("AST → LLVM IR: each node emits instructions and returns its result operand",
                 fontsize=12, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "lowering.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_lowering()
