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


def node(ax, x, y, label, color, ret, order, r=0.42, fontsize=16, ret_side="below"):
    """One AST node: its label, the visit number, and the operand it hands back."""
    ax.add_patch(plt.Circle((x, y), r, facecolor=color, edgecolor=EDGE, linewidth=1.3, zorder=3))
    ax.text(x, y, label, ha="center", va="center", fontsize=fontsize, fontweight="bold",
            color=TEXT, zorder=4)
    # visit order, in its own badge up-left: children before parents, left before right
    ax.add_patch(plt.Circle((x - r - 0.10, y + r + 0.10), 0.23, facecolor="#b4453a",
                            edgecolor="none", zorder=5))
    ax.text(x - r - 0.10, y + r + 0.10, str(order), ha="center", va="center", fontsize=11,
            fontweight="bold", color="white", zorder=6)
    dx, dy, ha = {"below": (0, -r - 0.34, "center"),
                  "right": (r + 0.18, 0, "left"),
                  "left": (-r - 0.18, 0, "right")}[ret_side]
    ax.text(x + dx, y + dy, ret, ha=ha, va="center", fontsize=12.5,
            color=REG, family="monospace", fontweight="bold", zorder=4)


def edge(ax, p0, p1):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-", linewidth=1.4, color=EDGE, zorder=1))


def make_lowering():
    fig, ax = plt.subplots(figsize=(11.4, 6.8))
    ax.set_xlim(0, 11.7)
    ax.set_ylim(-0.8, 7.35)
    ax.axis("off")

    call = (2.5, 5.7)
    plus = (2.5, 4.2)
    one = (1.0, 2.7)
    star = (4.0, 2.7)
    two = (3.1, 1.2)
    three = (4.9, 1.2)

    for a, b in ((call, plus), (plus, one), (plus, star), (star, two), (star, three)):
        edge(ax, a, b)

    # visit order is what emit_expr does: left operand, right operand, then the node
    node(ax, *call, "print", CALL, '-> "0"', 6, r=0.62, fontsize=13, ret_side="right")
    node(ax, *plus, "+", OP, "-> %t2", 5, ret_side="right")
    node(ax, *one, "1", LIT, "-> 1", 1, ret_side="left")
    node(ax, *star, "*", OP, "-> %t1", 4, ret_side="right")
    node(ax, *two, "2", LIT, "-> 2", 2)
    node(ax, *three, "3", LIT, "-> 3", 3)

    ax.text(2.5, 6.85, "AST of  print(1 + 2 * 3)", ha="center", va="center", fontsize=14,
            fontweight="bold", color=TEXT)
    ax.text(2.6, -0.30,
            "red = the order emit_expr visits the nodes — left operand, right operand,\n"
            "then the node itself.   green = the operand each node hands back.",
            ha="center", va="center", fontsize=11, color=TEXT, fontstyle="italic")

    # the IR panel, each line tagged with the node that emitted it
    px, py, pw, ph = 6.35, 1.35, 5.1, 4.9
    ax.add_patch(FancyBboxPatch((px, py), pw, ph, boxstyle="round,pad=0.03,rounding_size=0.1",
                                linewidth=1.2, edgecolor=EDGE, facecolor=CODE, zorder=2))
    ax.text(px + pw / 2, py + ph - 0.34, "the IR that comes out, in order",
            ha="center", va="center", fontsize=12.5, fontweight="bold", color=TEXT, zorder=3)

    lines = [
        (None, "nodes 1, 2, 3 emit nothing at all:", TEXT),
        (None, "a literal IS already an operand", TEXT),
        (4, "%t1 = mul i64 2, 3", REG),
        (5, "%t2 = add i64 1, %t1", REG),
        (6, "%t3 = call i32 (ptr, ...) @printf(", REG),
        (None, "         ptr @.fmt, i64 %t2)", REG),
    ]
    y = py + ph - 0.95
    for order, text, color in lines:
        if order is not None:
            ax.add_patch(plt.Circle((px + 0.36, y), 0.22, facecolor="#b4453a",
                                    edgecolor="none", zorder=3))
            ax.text(px + 0.36, y, str(order), ha="center", va="center", fontsize=10.5,
                    fontweight="bold", color="white", zorder=4)
        ax.text(px + 0.74, y, text, ha="left", va="center", fontsize=11.5,
                family="monospace", color=color, zorder=3)
        y -= 0.56

    ax.text(px + pw / 2, py + 0.34,
            "every %tN is defined before it is used, for free:\n"
            "a parent cannot run until its children have",
            ha="center", va="center", fontsize=10.5, color=TEXT, fontstyle="italic", zorder=3)

    ax.set_title("AST → LLVM IR: each node emits its instructions, then hands back one operand",
                 fontsize=14, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "lowering.png")
    fig.savefig(out, dpi=170, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_lowering()
