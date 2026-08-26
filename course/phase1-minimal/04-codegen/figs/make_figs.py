#!/usr/bin/env python3
"""Generate the figures embedded in 04-codegen/explainer.qmd.

Run from the course/ root (the Makefile's `figs` target does this for you):

    .venv/bin/python phase1-minimal/04-codegen/figs/make_figs.py

Produces:
    figs/lowering.png  — AST → LLVM IR for `print(1 + 2 * 3)`: each node, in
                         post-order, emits instructions and returns a result operand
                         (a literal or a `%tN` register).

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
CALL = "#e6dcf2"  # the call node
EDGE = "#5b6b7b"
TEXT = "#1b2733"
REG = "#2f6f4f"  # returned-operand chips


def node(ax, x, y, label, color, ret, r=0.40, fontsize=14, ret_right=False):
    ax.add_patch(plt.Circle((x, y), r, facecolor=color, edgecolor=EDGE, linewidth=1.3, zorder=3))
    ax.text(x, y, label, ha="center", va="center", fontsize=fontsize, fontweight="bold",
            color=TEXT, zorder=4)
    # the operand this node "returns" — beside the node when an edge leaves downward
    if ret_right:
        ax.text(x + r + 0.18, y, ret, ha="left", va="center", fontsize=10.5,
                color=REG, family="monospace", fontweight="bold", zorder=4)
    else:
        ax.text(x, y - r - 0.28, ret, ha="center", va="center", fontsize=10.5,
                color=REG, family="monospace", fontweight="bold", zorder=4)


def edge(ax, p0, p1):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-", linewidth=1.4, color=EDGE, zorder=1))


def make_lowering():
    fig, ax = plt.subplots(figsize=(9.4, 5.6))
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 6.8)
    ax.axis("off")

    call = (2.5, 5.5)
    plus = (2.5, 4.1)
    one = (1.1, 2.7)
    star = (3.9, 2.7)
    two = (3.0, 1.2)
    three = (4.8, 1.2)

    edge(ax, call, plus)
    edge(ax, plus, one)
    edge(ax, plus, star)
    edge(ax, star, two)
    edge(ax, star, three)

    node(ax, *call, "print", CALL, "-> \"0\"", r=0.52, fontsize=11, ret_right=True)
    node(ax, *plus, "+", OP, "-> %t2")
    node(ax, *one, "1", LIT, "-> 1")
    node(ax, *star, "*", OP, "-> %t1")
    node(ax, *two, "2", LIT, "-> 2")
    node(ax, *three, "3", LIT, "-> 3")

    ax.text(2.5, 6.55, "AST of  print(1 + 2 * 3)", ha="center", va="center", fontsize=12,
            fontweight="bold", color=TEXT)
    ax.text(2.5, 0.35, "green = the operand each node returns", ha="center", va="center",
            fontsize=9, color=REG, fontstyle="italic")

    # the IR panel (right), filled in post-order
    px, py, pw, ph = 6.0, 1.6, 3.7, 4.0
    ax.add_patch(FancyBboxPatch((px, py), pw, ph, boxstyle="round,pad=0.03,rounding_size=0.1",
                                linewidth=1.2, edgecolor=EDGE, facecolor=CODE, zorder=2))
    ax.text(px + pw / 2, py + ph - 0.32, "emitted IR  (post-order)", ha="center", va="center",
            fontsize=10.5, fontweight="bold", color=TEXT, zorder=3)
    lines = [
        ("visit 2, 3   ->  literals, no IR", TEXT),
        ("%t1 = mul i64 2, 3", REG),
        ("visit 1      ->  literal, no IR", TEXT),
        ("%t2 = add i64 1, %t1", REG),
        ("...from the print node, last:", TEXT),
        ("%t3 = call i32 (ptr, ...) @printf(", REG),
        ("          ptr @.fmt, i64 %t2)", REG),
    ]
    y = py + ph - 0.90
    for text, color in lines:
        ax.text(px + 0.22, y, text, ha="left", va="center", fontsize=9.5,
                family="monospace", color=color, zorder=3)
        y -= 0.46

    ax.set_title("AST → LLVM IR: each node emits instructions and returns its result operand",
                 fontsize=12, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "lowering.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_lowering()
