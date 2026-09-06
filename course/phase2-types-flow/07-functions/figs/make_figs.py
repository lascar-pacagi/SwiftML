#!/usr/bin/env python3
"""Figures for 07-functions/explainer.qmd.

    .venv/bin/python phase2-types-flow/07-functions/figs/make_figs.py

Produces:
    figs/twopass.png — why sema makes TWO passes: collect every function's signature
    first, then check the bodies. That order is what lets a function call itself
    (recursion) and lets a call appear before the function's declaration (forward ref).
    The two annotations point from the calls that need the table to the table entry
    that answers them — the whole argument of the figure in one glance.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = "#eef2f7"
TAB = "#fff3d6"
CHK = "#dceede"
EDGE = "#5b6b7b"
TEXT = "#1b2733"
HL = "#b5651d"
DIM = "#5b6b7b"


def box(ax, cx, cy, w, h, title, color):
    """A titled panel. Returns the y of the first body line."""
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                 boxstyle="round,pad=0.03,rounding_size=0.07", linewidth=1.3,
                 edgecolor=EDGE, facecolor=color, zorder=1))
    ax.text(cx, cy + h / 2 - 0.30, title, ha="center", va="center",
            fontsize=11.5, fontweight="bold", color=TEXT, zorder=4)
    return cy + h / 2 - 0.72


def code(ax, x, y, lines, size=9.5, color=TEXT, weight="normal"):
    """Left-aligned monospace lines; returns the y of each line drawn."""
    ys = []
    for i, ln in enumerate(lines):
        yy = y - i * 0.34
        ax.text(x, yy, ln, ha="left", va="center", fontsize=size,
                family="monospace", color=color, zorder=4, fontweight=weight)
        ys.append(yy)
    return ys


def stage_arrow(ax, x0, x1, y, label):
    ax.add_patch(FancyArrowPatch((x0, y), (x1, y), arrowstyle="-|>", mutation_scale=15,
                 linewidth=1.6, color=EDGE, zorder=5))
    ax.text((x0 + x1) / 2, y + 0.20, label, ha="center", va="bottom",
            fontsize=9.5, style="italic", color=DIM, zorder=5)


def make_twopass():
    fig, ax = plt.subplots(figsize=(12.6, 5.9))
    ax.set_xlim(0, 12.6)
    ax.set_ylim(0, 5.9)
    ax.axis("off")

    W, H, CY = 3.0, 3.3, 3.35
    x_src, x_tab, x_chk = 1.9, 6.3, 10.7

    # ---- source, with the two calls that need the table marked ①②  -----------
    y = box(ax, x_src, CY, W, H, "source items", SRC)
    src = code(ax, x_src - W / 2 + 0.18, y,
               ["print(fib(10))", "", "func fib(_ n: Int) -> Int {",
                "  if n < 2 { return n }", "  return fib(n-1) + fib(n-2)", "}"], size=8.8)
    for mark, yy in (("[1]", src[0]), ("[2]", src[4])):
        ax.text(x_src + W / 2 - 0.22, yy, mark, ha="right", va="center",
                fontsize=11, color=HL, fontweight="bold", zorder=4)

    # ---- pass 1: one entry, and it is what both marks resolve to -------------
    y = box(ax, x_tab, CY, W, H, "pass 1 — signatures", TAB)
    ax.text(x_tab, y - 0.05, "not one line of a body\nis looked at yet",
            ha="center", va="center", fontsize=9, style="italic", color=DIM, zorder=4)
    ax.text(x_tab, y - 1.05, "fib : (Int) -> Int", ha="center", va="center",
            fontsize=10.5, family="monospace", color=TEXT, zorder=4)
    ax.text(x_tab, y - 1.48, "the one entry [1] and [2] resolve to", ha="center", va="center",
            fontsize=9, color=HL, fontweight="bold", zorder=4)

    # ---- pass 2 -------------------------------------------------------------
    y = box(ax, x_chk, CY, W, H, "pass 2 — check bodies", CHK)
    code(ax, x_chk - W / 2 + 0.18, y,
         ["fib's body:", "  fib(n-1)  ✓ found", "  fib(n-2)  ✓ found  [2]", "",
          "top level:", "  fib(10)   ✓ found  [1]"], size=8.8)

    # ---- the two stage arrows, alone in their gaps ---------------------------
    for x0, x1, label in ((x_src + W / 2, x_tab - W / 2, "scan\ndeclarations"),
                          (x_tab + W / 2, x_chk - W / 2, "resolve\ncalls")):
        ax.add_patch(FancyArrowPatch((x0 + 0.12, CY), (x1 - 0.12, CY),
                     arrowstyle="-|>", mutation_scale=15, linewidth=1.7, color=EDGE, zorder=5))
        ax.text((x0 + x1) / 2, CY + 0.22, label, ha="center", va="bottom",
                fontsize=9, style="italic", color=DIM, zorder=5, linespacing=1.25)

    # ---- what the two marks are, spelled out under the source ---------------
    ax.text(x_src - W / 2, 1.15,
            "[1] forward reference — the call is written before the func\n"
            "[2] recursion — fib calls itself, inside its own body",
            ha="left", va="center", fontsize=9.5, color=HL, zorder=6, linespacing=1.5)
    ax.text(6.3, 0.42,
            "Both are answered by the SAME entry — pass 1 wrote it before pass 2 asked,\n"
            "so where a call sits in the file stops mattering.",
            ha="center", va="center", fontsize=10, color=TEXT, zorder=6, linespacing=1.4)

    ax.set_title("Two passes: every signature first, then the bodies", fontsize=13,
                 color=TEXT, pad=10)
    fig.tight_layout()
    out = os.path.join(HERE, "twopass.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_twopass()
