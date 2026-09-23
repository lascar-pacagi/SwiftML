#!/usr/bin/env python3
"""Figures for 07-functions/explainer.qmd.

    .venv/bin/python phase2-types-flow/07-functions/figs/make_figs.py

Produces:
    figs/twopass.png — why sema makes TWO passes, as a comparison matrix. The same two
    calls are asked under both walk orders, and the only thing that differs is what the
    signature table holds at the moment each one is asked. Showing only the working order
    makes two passes look like a choice somebody made; asking the same questions of both
    makes it the fix, and puts the reason — the table — in the one column they share.
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


def panel(ax, x, y, w, h, face, edge, lw=1.4, z=0):
    ax.add_patch(FancyBboxPatch((x, y), w, h,
                 boxstyle="round,pad=0.04,rounding_size=0.10", linewidth=lw,
                 edgecolor=edge, facecolor=face, zorder=z))


def marker(ax, x, y, text, colour, r=0.26):
    ax.add_patch(plt.Circle((x, y), r, facecolor=colour, edgecolor="none", zorder=6))
    ax.text(x, y, text, ha="center", va="center", fontsize=13, fontweight="bold",
            color="white", zorder=7)


def make_twopass():
    fig, ax = plt.subplots(figsize=(15.0, 9.1))
    ax.set_xlim(0, 15.0)
    ax.set_ylim(-0.35, 9.0)
    ax.axis("off")

    # =========================== the program, across the top ======================
    panel(ax, 0.3, 6.05, 14.4, 2.35, SRC, EDGE)
    src = ["print(fib(10))", "func fib(_ n: Int) -> Int {", "  if n < 2 { return n }",
           "  return fib(n-1) + fib(n-2)", "}"]
    y = 7.96
    for i, ln in enumerate(src):
        ax.text(0.75, y, ln, ha="left", va="center", fontsize=15, family="monospace",
                color=TEXT, zorder=4)
        if i == 0:
            marker(ax, 5.35, y, "1", HL)
            ax.text(5.80, y, "a forward reference \u2014 the call is above the func",
                    ha="left", va="center", fontsize=14, color=HL, zorder=4)
        if i == 3:
            marker(ax, 5.35, y, "2", HL)
            ax.text(5.80, y, "recursion \u2014 fib calls itself, inside its own body",
                    ha="left", va="center", fontsize=14, color=HL, zorder=4)
        y -= 0.45

    # the thesis, in the panel's own empty right-hand column
    ax.text(5.80, 7.40, "Both calls are fine. What decides whether they",
            ha="left", va="center", fontsize=14.5, color=TEXT, zorder=4)
    ax.text(5.80, 7.07, "resolve is what the table holds when each is ASKED.",
            ha="left", va="center", fontsize=14.5, color=TEXT, zorder=4)

    # =========================== the matrix =======================================
    COL1, COL2 = 6.55, 11.05        # centres of the two question columns
    ROWA, ROWB = 3.70, 1.16         # centres of the two regime rows
    CW, RH = 4.10, 2.05

    # column headings
    for cx, badge, label in [(COL1, "1", "the forward reference"),
                             (COL2, "2", "the recursive call")]:
        marker(ax, cx - 1.55, 5.14, badge, HL)
        ax.text(cx - 1.18, 5.14, label, ha="left", va="center", fontsize=14.5,
                fontweight="bold", color=TEXT, zorder=4)

    # row headings
    ax.text(3.95, ROWA + 0.38, "one pass", ha="right", va="center", fontsize=16,
            fontweight="bold", color=BAD, zorder=4)
    ax.text(3.95, ROWA - 0.05, "top to bottom", ha="right", va="center", fontsize=13,
            color=BAD, style="italic", zorder=4)
    ax.text(3.95, ROWA - 0.52, "the table is built as", ha="right", va="center",
            fontsize=12.5, color=DIM, zorder=4)
    ax.text(3.95, ROWA - 0.86, "the walk goes", ha="right", va="center",
            fontsize=12.5, color=DIM, zorder=4)

    ax.text(3.95, ROWB + 0.38, "two passes", ha="right", va="center", fontsize=16,
            fontweight="bold", color=GOOD, zorder=4)
    ax.text(3.95, ROWB - 0.05, "signatures, then bodies", ha="right", va="center",
            fontsize=13, color=GOOD, style="italic", zorder=4)
    ax.text(3.95, ROWB - 0.52, "the table is finished", ha="right", va="center",
            fontsize=12.5, color=DIM, zorder=4)
    ax.text(3.95, ROWB - 0.86, "before any body is read", ha="right", va="center",
            fontsize=12.5, color=DIM, zorder=4)

    # the four cells
    def cell(cx, cy, face, edge, table, verdict_text, verdict_colour, ok):
        panel(ax, cx - CW / 2, cy - RH / 2, CW, RH, face, edge, lw=1.3)
        ax.text(cx, cy + 0.62, "the table holds", ha="center", va="center",
                fontsize=12.5, color=DIM, style="italic", zorder=4)
        ax.text(cx, cy + 0.19, table, ha="center", va="center", fontsize=14.5,
                family="monospace", color=TEXT, zorder=4)
        ax.plot([cx - CW / 2 + 0.35, cx + CW / 2 - 0.35], [cy - 0.22, cy - 0.22],
                color=edge, linewidth=1, alpha=0.45, zorder=3)
        ax.text(cx, cy - 0.62, ("\u2713  " if ok else "\u2717  ") + verdict_text,
                ha="center", va="center", fontsize=14.5, fontweight="bold",
                color=verdict_colour, zorder=4, family="monospace")

    cell(COL1, ROWA, BADBG, BAD, "(nothing yet)", "cannot find 'fib'", BAD, False)
    cell(COL2, ROWA, BADBG, BAD, "(still nothing)", "cannot find 'fib'", BAD, False)
    cell(COL1, ROWB, "#f2f8f3", GOOD, "fib : (Int) -> Int", "resolved", GOOD, True)
    cell(COL2, ROWB, "#f2f8f3", GOOD, "fib : (Int) -> Int", "resolved", GOOD, True)

    # the divider between the two regimes: the figure is a BEFORE and an AFTER, and the
    # rule is what says so — without it the four cells read as one four-part list
    mid = (ROWA - RH / 2 + ROWB + RH / 2) / 2
    ax.plot([1.78, 13.65], [mid, mid], color="#c9d3dc", linewidth=1.3,
            linestyle=(0, (6, 5)), zorder=1)
    ax.text(0.88, mid, "same\nquestions,\nasked again", ha="center", va="center",
            fontsize=12, color=DIM, style="italic", zorder=4)

    # the one entry answers both — drawn as a brace under the green row
    ax.text(8.8, -0.20, "the SAME entry, written by pass 1 before either call was asked",
            ha="center", va="center", fontsize=13.5, color=GOOD, style="italic", zorder=4)

    ax.set_title("Two passes: the same two calls, and the only thing that differs is "
                 "what the table holds",
                 fontsize=17, color=TEXT, pad=16)
    fig.tight_layout()
    out = os.path.join(HERE, "twopass.png")
    fig.savefig(out, dpi=165, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_twopass()
