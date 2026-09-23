#!/usr/bin/env python3
"""Figures for 07-functions/explainer.qmd.

    .venv/bin/python phase2-types-flow/07-functions/figs/make_figs.py

Produces:
    figs/twopass.png — why sema makes TWO passes, shown as the COUNTERFACTUAL: the same
    program checked top-to-bottom, where both the forward reference and the recursive
    call fail, and then checked in two passes, where the same two calls are answered by
    a table that was already complete when they were asked. Showing only the working
    order makes two passes look like a choice; showing the failing one makes it the fix.
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
BAD = "#b4453a"
BADBG = "#fdf4f3"
GOOD = "#2f6f4f"


def box(ax, cx, cy, w, h, title, color):
    """A titled panel. Returns the y of the first body line."""
    ax.add_patch(FancyBboxPatch((cx - w / 2, cy - h / 2), w, h,
                 boxstyle="round,pad=0.03,rounding_size=0.07", linewidth=1.3,
                 edgecolor=EDGE, facecolor=color, zorder=1))
    ax.text(cx, cy + h / 2 - 0.34, title, ha="center", va="center",
            fontsize=14.5, fontweight="bold", color=TEXT, zorder=4)
    return cy + h / 2 - 0.86


def code(ax, x, y, lines, size=12.5, color=TEXT, weight="normal"):
    """Left-aligned monospace lines; returns the y of each line drawn."""
    ys = []
    for i, ln in enumerate(lines):
        yy = y - i * 0.43
        ax.text(x, yy, ln, ha="left", va="center", fontsize=size,
                family="monospace", color=color, zorder=4, fontweight=weight)
        ys.append(yy)
    return ys


def stage_arrow(ax, x0, x1, y, label):
    ax.add_patch(FancyArrowPatch((x0, y), (x1, y), arrowstyle="-|>", mutation_scale=15,
                 linewidth=1.6, color=EDGE, zorder=5))
    ax.text((x0 + x1) / 2, y + 0.22, label, ha="center", va="bottom",
            fontsize=12, style="italic", color=DIM, zorder=5)


def marker(ax, x, y, text, colour, r=0.22):
    ax.add_patch(plt.Circle((x, y), r, facecolor=colour, edgecolor="none", zorder=5))
    ax.text(x, y, text, ha="center", va="center", fontsize=11.5, fontweight="bold",
            color="white", zorder=6)


def verdict(ax, x, y, ok, text, colour, size=12.5):
    ax.text(x, y, ("\u2713 " if ok else "\u2717 ") + text, ha="left", va="center",
            fontsize=size, color=colour, fontweight="bold", zorder=4, family="monospace")


def make_twopass():
    fig, ax = plt.subplots(figsize=(15.8, 8.6))
    ax.set_xlim(0, 16.3)
    ax.set_ylim(0, 8.8)
    ax.axis("off")

    # ---- the program, once, on the left -------------------------------------------
    box(ax, 2.62, 5.05, 4.9, 5.5, "one program", SRC)
    lines = ["print(fib(10))", "", "func fib(_ n: Int) -> Int {", "  if n < 2 { return n }",
             "  return fib(n-1) + fib(n-2)", "}"]
    ys = code(ax, 0.42, 6.95, lines, size=12.5)
    marker(ax, 4.72, ys[0], "1", HL)
    marker(ax, 4.72, ys[4], "2", HL)

    ax.plot([0.50, 4.80], [4.58, 4.58], color="#d3dce4", linewidth=1.1, zorder=2)
    marker(ax, 0.76, 4.18, "1", HL, r=0.20)
    ax.text(1.10, 4.18, "a forward reference \u2014 the call", ha="left", va="center",
            fontsize=12, color=HL, zorder=4)
    ax.text(1.10, 3.86, "is written above the func", ha="left", va="center",
            fontsize=12, color=HL, zorder=4)
    marker(ax, 0.76, 3.38, "2", HL, r=0.20)
    ax.text(1.10, 3.38, "recursion \u2014 fib calls itself,", ha="left", va="center",
            fontsize=12, color=HL, zorder=4)
    ax.text(1.10, 3.06, "inside its own body", ha="left", va="center",
            fontsize=12, color=HL, zorder=4)

    # ---- ROW 1: one pass, top to bottom — both fail --------------------------------
    ax.add_patch(FancyBboxPatch((5.35, 4.72), 10.45, 3.18,
                 boxstyle="round,pad=0.04,rounding_size=0.09", linewidth=1.4,
                 edgecolor=BAD, facecolor=BADBG, zorder=0))
    ax.text(5.72, 7.50, "checked top to bottom, one pass", ha="left", va="center",
            fontsize=14.5, fontweight="bold", color=BAD, zorder=4)
    ax.text(5.72, 7.08, "the table is built as the walk goes, so it is never ahead of it",
            ha="left", va="center", fontsize=12, color=BAD, style="italic", zorder=4)

    ax.text(5.95, 6.52, "at", ha="left", va="center", fontsize=12.5, color=TEXT, zorder=4)
    marker(ax, 6.36, 6.52, "1", HL, r=0.20)
    ax.text(6.66, 6.52, "the table holds:", ha="left", va="center", fontsize=12.5,
            color=TEXT, zorder=4)
    ax.text(6.25, 6.08, "(nothing yet)", ha="left", va="center", fontsize=12.5,
            family="monospace", color=DIM, zorder=4)
    verdict(ax, 5.95, 5.52, False, "cannot find 'fib' in scope", BAD)

    ax.plot([10.75, 10.75], [5.12, 6.84], color="#e6cdca", linewidth=1.2, zorder=1)

    ax.text(11.00, 6.52, "at", ha="left", va="center", fontsize=12.5, color=TEXT, zorder=4)
    marker(ax, 11.41, 6.52, "2", HL, r=0.20)
    ax.text(11.71, 6.52, "the table holds:", ha="left", va="center", fontsize=12.5,
            color=TEXT, zorder=4)
    ax.text(11.30, 6.08, "(still nothing \u2014 fib is", ha="left", va="center",
            fontsize=12.5, family="monospace", color=DIM, zorder=4)
    ax.text(11.30, 5.72, " not finished being read)", ha="left", va="center",
            fontsize=12.5, family="monospace", color=DIM, zorder=4)
    verdict(ax, 11.00, 5.24, False, "cannot find 'fib' in scope", BAD)

    ax.text(10.55, 4.96, "neither call is wrong \u2014 the ORDER of the walk is",
            ha="center", va="center", fontsize=12, color=BAD, style="italic", zorder=4)

    # ---- ROW 2: two passes — both answered -----------------------------------------
    ax.add_patch(FancyBboxPatch((5.35, 0.42), 10.45, 3.92,
                 boxstyle="round,pad=0.04,rounding_size=0.09", linewidth=1.4,
                 edgecolor=GOOD, facecolor="#f2f8f3", zorder=0))
    ax.text(5.72, 3.96, "checked in two passes", ha="left", va="center",
            fontsize=14.5, fontweight="bold", color=GOOD, zorder=4)

    box(ax, 7.92, 1.95, 4.25, 2.72, "pass 1 \u2014 signatures only", TAB)
    ax.text(7.92, 2.52, "fib : (Int) -> Int", ha="center", va="center", fontsize=13.5,
            family="monospace", color=TEXT, zorder=4)
    ax.text(7.92, 1.98, "not one line of a body", ha="center", va="center", fontsize=12,
            color=DIM, style="italic", zorder=4)
    ax.text(7.92, 1.66, "is looked at yet", ha="center", va="center", fontsize=12,
            color=DIM, style="italic", zorder=4)
    ax.text(7.92, 1.16, "so the order it reads them", ha="center", va="center",
            fontsize=12, color=GOOD, zorder=4)
    ax.text(7.92, 0.86, "in cannot matter", ha="center", va="center",
            fontsize=12, color=GOOD, zorder=4)

    stage_arrow(ax, 10.15, 11.20, 1.95, "then ask it")

    box(ax, 13.55, 1.95, 4.25, 2.72, "pass 2 \u2014 check bodies", CHK)
    marker(ax, 11.78, 2.52, "1", HL, r=0.20)
    verdict(ax, 12.06, 2.52, True, "fib(10)", GOOD)
    marker(ax, 11.78, 2.04, "2", HL, r=0.20)
    verdict(ax, 12.06, 2.04, True, "fib(n-1), fib(n-2)", GOOD)
    ax.text(13.55, 1.46, "both answered by the ONE entry", ha="center", va="center",
            fontsize=12, color=GOOD, style="italic", zorder=4)
    ax.text(13.55, 1.16, "pass 1 wrote, before either", ha="center", va="center",
            fontsize=12, color=GOOD, style="italic", zorder=4)
    ax.text(13.55, 0.86, "was asked", ha="center", va="center",
            fontsize=12, color=GOOD, style="italic", zorder=4)

    ax.set_title("Where a call sits in the file stops mattering \u2014 if the table is "
                 "finished before any body is read",
                 fontsize=16, color=TEXT, pad=16)
    fig.tight_layout()
    out = os.path.join(HERE, "twopass.png")
    fig.savefig(out, dpi=165, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_twopass()
