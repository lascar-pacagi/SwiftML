#!/usr/bin/env python3
"""Figures for 41-constraint-solver/explainer.qmd.

    .venv/bin/python phase9-inference/41-constraint-solver/figs/make_figs.py

Produces:
    figs/solve.png — one program through all three phases: csgen writes the system down,
    cssolver searches it, csapply writes the answer onto the tree. The program is the one
    a bidirectional checker cannot do at all — overloaded on the return type alone.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
PANEL = "#f3f6f8"
EDGE = "#5b6b7b"
TEXT = "#1b2733"
OK = "#2f6f4f"
NO = "#b4453a"
VAR = "#b5651d"
LINE = "#c9d3dc"


def panel(ax, x, y, w, h, title):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.12",
                                linewidth=1.3, edgecolor=LINE, facecolor=PANEL, zorder=1))
    ax.text(x + w / 2, y + h - 0.32, title, ha="center", va="center", fontsize=11.5,
            fontweight="bold", color=TEXT, zorder=3)


def mono(ax, x, y, text, size=10.5, color=TEXT, weight="normal", ha="left"):
    ax.text(x, y, text, ha=ha, va="center", fontsize=size, family="monospace",
            color=color, fontweight=weight, zorder=3)


def flow(ax, x0, x1, y, label):
    ax.add_patch(FancyArrowPatch((x0, y), (x1, y), arrowstyle="-|>", mutation_scale=15,
                                 linewidth=1.8, color=EDGE, zorder=4))
    ax.text((x0 + x1) / 2, y + 0.26, label, ha="center", va="center", fontsize=9.5,
            color=EDGE, fontstyle="italic", zorder=4)


def make_solve():
    fig, ax = plt.subplots(figsize=(13.4, 6.4))
    ax.set_xlim(0, 15.2)
    ax.set_ylim(-0.1, 6.6)
    ax.axis("off")

    # ---- the program ---------------------------------------------------------------
    panel(ax, 0.2, 3.3, 3.3, 2.6, "the program")
    for i, line in enumerate(["func g() -> Int {", "  return 1", "}",
                              "func g() -> Double {", "  return 2.5", "}",
                              "let d: Int = g()"]):
        mono(ax, 0.45, 5.24 - i * 0.29, line, size=9.5,
             color=OK if i == 6 else TEXT, weight="bold" if i == 6 else "normal")
    ax.text(1.85, 2.95, "two functions, one name —\nnothing about `g()` says which",
            ha="center", va="center", fontsize=9, color=TEXT, fontstyle="italic")

    flow(ax, 3.62, 4.3, 4.6, "csgen")

    # ---- the constraint system -----------------------------------------------------
    panel(ax, 4.4, 3.3, 4.2, 2.6, "the system it writes down")
    mono(ax, 4.65, 5.24, "$T0", size=10, color=VAR, weight="bold")
    ax.text(5.15, 5.24, "\u2014 the call's result, still unknown", ha="left", va="center",
            fontsize=8.8, color=VAR, fontstyle="italic", zorder=3)
    mono(ax, 4.65, 4.90, "g is one of {", size=10)
    mono(ax, 4.95, 4.58, "#0  [ $T0 == Int    ]", size=10)
    mono(ax, 4.95, 4.26, "#1  [ $T0 == Double ]", size=10)
    mono(ax, 4.65, 3.94, "}", size=10)
    ax.plot([4.62, 8.38], [3.74, 3.74], color=LINE, linewidth=1)
    mono(ax, 4.65, 3.54, "$T0 == Int", size=10, color=OK, weight="bold")
    ax.text(6.5, 3.05, "the annotation, stated as one more fact", ha="center",
            va="center", fontsize=8.8, color=OK, fontstyle="italic")

    ax.add_patch(FancyArrowPatch((6.5, 2.92), (6.5, 2.62), arrowstyle="-|>",
                                 mutation_scale=15, linewidth=1.8, color=EDGE, zorder=4))
    ax.text(6.78, 2.77, "cssolver", ha="left", va="center", fontsize=9.5, color=EDGE,
            fontstyle="italic")

    # ---- the search ----------------------------------------------------------------
    panel(ax, 4.4, 0.2, 4.2, 2.3, "the search")
    mono(ax, 6.5, 1.98, "$T0 == Int", size=10, color=OK, ha="center")
    for dx, label, colour, verdict in [(-1.15, "try #0", OK, "✓"),
                                       (1.15, "try #1", NO, "✗")]:
        ax.add_patch(FancyArrowPatch((6.5, 1.82), (6.5 + dx, 1.36), arrowstyle="-|>",
                                     mutation_scale=12, linewidth=1.5, color=colour,
                                     zorder=3))
        mono(ax, 6.5 + dx, 1.16, label, size=9.5, color=colour, ha="center",
             weight="bold")
    mono(ax, 5.35, 0.94, "Int == Int", size=9, color=OK, ha="center")
    mono(ax, 5.35, 0.66, "✓ a solution", size=9, color=OK, ha="center", weight="bold")
    mono(ax, 7.65, 0.94, "Double == Int", size=9, color=NO, ha="center")
    mono(ax, 7.65, 0.66, "✗ undo the scope", size=9, color=NO, ha="center",
         weight="bold")
    ax.text(6.5, 0.34, "one alternative survives, so the call is resolved",
            ha="center", va="center", fontsize=8.5, color=TEXT, fontstyle="italic")

    flow(ax, 8.72, 9.4, 4.6, "csapply")

    # ---- the typed tree ------------------------------------------------------------
    panel(ax, 9.5, 3.3, 5.4, 2.6, "the tree it hands back")
    mono(ax, 9.75, 5.24, "(let d (g#0 : Int))", size=11, color=OK, weight="bold")
    ax.text(9.75, 4.80, "the DECLARATION, not just the name:", ha="left", va="center",
            fontsize=9, color=TEXT)
    ax.text(9.75, 4.50, "`g#0` is the first `g` in source order,", ha="left", va="center",
            fontsize=9, color=TEXT)
    ax.text(9.75, 4.20, "and SILGen emits a call to `g$0`.", ha="left", va="center",
            fontsize=9, color=TEXT)
    ax.plot([9.72, 14.68], [3.95, 3.95], color=LINE, linewidth=1)
    ax.text(9.75, 3.62, "Nothing downstream resolves an overload again —\nthat is the whole"
            " output of the pass.", ha="left", va="center", fontsize=8.8, color=TEXT,
            fontstyle="italic")

    ax.text(11.6, 1.9,
            "Swap `Int` for `Double` on the left\nand the SAME call site resolves to `g#1`.\n"
            "No rule that looks only at `g()`\ncan tell the two apart.",
            ha="center", va="center", fontsize=10, color=TEXT)
    ax.add_patch(FancyBboxPatch((9.5, 0.9), 4.2, 2.0,
                                boxstyle="round,pad=0.04,rounding_size=0.12", linewidth=1.3,
                                edgecolor=NO, facecolor="#fdf4f3", zorder=0))
    ax.text(11.6, 0.55, "why `infer` cannot do this", ha="center", va="center",
            fontsize=10.5, fontweight="bold", color=NO)

    ax.set_title("Generate, solve, apply — the three passes swiftc splits a type checker into",
                 fontsize=13.5, color=TEXT, pad=12)
    fig.tight_layout()
    out = os.path.join(HERE, "solve.png")
    fig.savefig(out, dpi=165, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_solve()
