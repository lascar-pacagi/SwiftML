#!/usr/bin/env python3
"""Figures for 07-functions/explainer.qmd.

    .venv/bin/python phase2-types-flow/07-functions/figs/make_figs.py

Produces:
    figs/break.png — the same function as an AST and as a CFG. In the tree, `break` is a
    LEAF: nothing in it records where control goes next, so "does every path return"
    cannot be answered without reconstructing that. In the graph it is an edge, and the
    question collapses into asking whether the block after the loop is reachable.

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
    fig, ax = plt.subplots(figsize=(15.0, 9.4))
    ax.set_xlim(0, 15.0)
    ax.set_ylim(-0.55, 9.15)
    ax.axis("off")

    # =========================== the program, across the top ======================
    panel(ax, 0.3, 5.92, 14.4, 2.92, SRC, EDGE)
    src = ["print(g())", "func g() -> Int { return 1 }", "func fib(_ n: Int) -> Int {",
           "  if n < 2 { return n }", "  return fib(n-1) + fib(n-2)", "}"]
    y = 8.46
    for i, ln in enumerate(src):
        ax.text(0.75, y, ln, ha="left", va="center", fontsize=15, family="monospace",
                color=TEXT, zorder=4)
        if i == 0:
            marker(ax, 5.90, y, "1", HL)
            ax.text(6.35, y, "a forward reference \u2014 g is declared BELOW",
                    ha="left", va="center", fontsize=14, color=HL, zorder=4)
        if i == 4:
            marker(ax, 5.90, y, "2", HL)
            ax.text(6.35, y, "recursion \u2014 fib calls ITSELF, inside its own body",
                    ha="left", va="center", fontsize=14, color=HL, zorder=4)
        y -= 0.45

    # the thesis, in the panel's own empty right-hand column
    ax.text(6.35, 7.66, "Both calls are fine. What decides whether they",
            ha="left", va="center", fontsize=14.5, color=TEXT, zorder=4)
    ax.text(6.35, 7.33, "resolve is what the table holds when each is ASKED.",
            ha="left", va="center", fontsize=14.5, color=TEXT, zorder=4)

    # =========================== the matrix =======================================
    COL1, COL2 = 6.55, 11.05        # centres of the two question columns
    ROWA, ROWB = 3.60, 1.06         # centres of the two regime rows
    CW, RH = 4.10, 2.25

    # column headings
    for cx, badge, label in [(COL1, "1", "the forward reference"),
                             (COL2, "2", "the recursive call")]:
        marker(ax, cx - 1.55, 5.08, badge, HL)
        ax.text(cx - 1.18, 5.08, label, ha="left", va="center", fontsize=14.5,
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
        ax.text(cx, cy + 0.70, "the table holds", ha="center", va="center",
                fontsize=12.5, color=DIM, style="italic", zorder=4)
        ty = cy + 0.30 if len(table) > 1 else cy + 0.16
        for line, colour in table:
            ax.text(cx, ty, line, ha="center", va="center", fontsize=13.5,
                    family="monospace", color=colour, zorder=4)
            ty -= 0.36
        ax.plot([cx - CW / 2 + 0.35, cx + CW / 2 - 0.35], [cy - 0.34, cy - 0.34],
                color=edge, linewidth=1, alpha=0.45, zorder=3)
        ax.text(cx, cy - 0.72, ("\u2713  " if ok else "\u2717  ") + verdict_text,
                ha="center", va="center", fontsize=14.5, fontweight="bold",
                color=verdict_colour, zorder=4, family="monospace")

    # at (2) under one pass the table is NOT empty — it holds g, read on the way past.
    # It just does not hold the one thing being asked for, which is the sharper failure.
    cell(COL1, ROWA, BADBG, BAD, [("(nothing yet)", DIM)], "cannot find 'g'", BAD, False)
    cell(COL2, ROWA, BADBG, BAD, [("g : () -> Int", TEXT), ("...but not fib", DIM)],
         "cannot find 'fib'", BAD, False)
    both = [("g   : () -> Int", TEXT), ("fib : (Int) -> Int", TEXT)]
    cell(COL1, ROWB, "#f2f8f3", GOOD, both, "resolved", GOOD, True)
    cell(COL2, ROWB, "#f2f8f3", GOOD, both, "resolved", GOOD, True)

    # the divider between the two regimes: the figure is a BEFORE and an AFTER, and the
    # rule is what says so — without it the four cells read as one four-part list
    mid = (ROWA - RH / 2 + ROWB + RH / 2) / 2
    ax.plot([1.78, 13.65], [mid, mid], color="#c9d3dc", linewidth=1.3,
            linestyle=(0, (6, 5)), zorder=1)
    ax.text(0.88, mid, "same\nquestions,\nasked again", ha="center", va="center",
            fontsize=12, color=DIM, style="italic", zorder=4)

    # the one entry answers both — drawn as a brace under the green row
    ax.text(8.8, -0.38, "the whole table, written by pass 1 before either call was asked",
            ha="center", va="center", fontsize=13.5, color=GOOD, style="italic", zorder=4)

    ax.set_title("Two passes: the same two calls, and the only thing that differs is "
                 "what the table holds",
                 fontsize=17, color=TEXT, pad=16)
    fig.tight_layout()
    out = os.path.join(HERE, "twopass.png")
    fig.savefig(out, dpi=165, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


def node(ax, x, y, label, face, edge, r=0.40, size=12, tcol=None):
    ax.add_patch(plt.Circle((x, y), r, facecolor=face, edgecolor=edge, linewidth=1.4,
                            zorder=4))
    ax.text(x, y, label, ha="center", va="center", fontsize=size, fontweight="bold",
            color=tcol or TEXT, zorder=5)


def blk(ax, x, y, w, h, lines, face, edge, size=13.5):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                 boxstyle="round,pad=0.03,rounding_size=0.07", linewidth=1.5,
                 edgecolor=edge, facecolor=face, zorder=4))
    ly = y + (len(lines) - 1) * 0.17
    for t in lines:
        ax.text(x, ly, t, ha="center", va="center", fontsize=size, family="monospace",
                color=TEXT, zorder=5)
        ly -= 0.34


def link(ax, p0, p1, colour=EDGE, rad=0.0, lw=1.5, style="-|>", dash=None, z=3):
    kw = dict(arrowstyle=style, mutation_scale=14, linewidth=lw, color=colour, zorder=z,
              connectionstyle=f"arc3,rad={rad}")
    if dash:
        kw["linestyle"] = dash
    ax.add_patch(FancyArrowPatch(p0, p1, **kw))


def make_break():
    fig, ax = plt.subplots(figsize=(16.4, 9.0))
    ax.set_xlim(0, 16.4)
    ax.set_ylim(0, 9.4)
    ax.axis("off")

    ax.text(8.2, 8.86, "func f(_ c: Bool) -> Int { while true { if c { break }; return 1 } }",
            ha="center", va="center", fontsize=17, family="monospace", color=TEXT)
    ax.text(8.2, 8.42, "swiftc rejects it: missing return. Where does the `break` go?",
            ha="center", va="center", fontsize=15, color=DIM, style="italic")

    # ------------------------------- the AST ------------------------------------------
    ax.text(3.9, 7.66, "as an AST \u2014 a tree", ha="center", va="center", fontsize=17,
            fontweight="bold", color=TEXT)

    W, CND, IF, VC, BR, RET = (3.5, 6.70), (5.6, 6.70), (2.4, 5.30), (0.95, 5.30), \
                              (2.4, 3.80), (5.1, 5.30)
    for p0, p1 in [(W, CND), (W, IF), (W, RET), (IF, VC), (IF, BR)]:
        link(ax, p0, p1, EDGE, style="-", lw=1.5, z=2)
    node(ax, *W, "while", "#fff3d6", EDGE, r=0.54, size=14)
    node(ax, *CND, "true", CHK, EDGE, r=0.46, size=13)
    node(ax, *IF, "if", "#fff3d6", EDGE, r=0.44, size=14)
    node(ax, *VC, "c", CHK, EDGE, r=0.40, size=13)
    node(ax, *RET, "return", CHK, EDGE, r=0.58, size=13)
    node(ax, *BR, "break", BADBG, BAD, r=0.54, size=13, tcol=BAD)

    link(ax, (2.4, 3.22), (2.4, 2.44), BAD, lw=1.8, dash=(0, (4, 3)))
    ax.text(2.4, 2.12, "goes WHERE?", ha="center", va="center", fontsize=15,
            color=BAD, fontweight="bold")
    ax.text(3.9, 1.44, "`break` is a LEAF. Its parent is the `if` it sits in,\n"
            "and nothing in the tree records the loop it exits\n"
            "or what runs after that loop ends.",
            ha="center", va="center", fontsize=14.5, color=TEXT)
    ax.text(3.9, 0.42, "\u2717  the tree cannot answer it", ha="center", va="center",
            fontsize=16, fontweight="bold", color=BAD, family="monospace")

    ax.plot([7.9, 7.9], [0.2, 8.02], color="#d3dce4", linewidth=1.4,
            linestyle=(0, (6, 5)))

    # ------------------------------- the CFG ------------------------------------------
    ax.text(12.45, 7.66, "as a CFG \u2014 a graph", ha="center", va="center", fontsize=17,
            fontweight="bold", color=TEXT)

    hdr, tst, ret, aft = (10.4, 6.70), (10.4, 5.30), (10.4, 3.80), (14.5, 5.30)
    blk(ax, *hdr, 2.7, 0.68, ["header"], CHK, EDGE)
    blk(ax, *tst, 2.7, 0.68, ["if c"], CHK, EDGE)
    blk(ax, *ret, 2.7, 0.68, ["return 1"], CHK, EDGE)
    blk(ax, *aft, 2.9, 0.68, ["after the loop"], BADBG, BAD)

    link(ax, (hdr[0], hdr[1] - 0.36), (tst[0], tst[1] + 0.36), lw=1.7)
    ax.text(10.18, 6.02, "always \u2014 `true`", ha="right", va="center",
            fontsize=13, color=DIM, style="italic")

    # the two sides of `if c`, labelled as the SAME test
    link(ax, (tst[0] + 1.36, tst[1]), (aft[0] - 1.47, aft[1]), BAD, lw=2.1)
    ax.text(12.60, 5.72, "c true", ha="center", va="center", fontsize=13,
            color=BAD, fontweight="bold")
    ax.text(12.60, 5.42, "break", ha="center", va="center", fontsize=13,
            color=BAD, fontweight="bold", family="monospace")

    link(ax, (tst[0], tst[1] - 0.36), (ret[0], ret[1] + 0.36), lw=1.7)
    ax.text(10.62, 4.56, "c false", ha="left", va="center", fontsize=13, color=DIM,
            style="italic")

    # the two ways out of the function, which is the whole comparison
    link(ax, (ret[0], ret[1] - 0.36), (ret[0], 2.74), GOOD, lw=1.9)
    ax.text(10.4, 2.44, "\u2713 exits WITH a value", ha="center", va="center",
            fontsize=13.5, color=GOOD, fontweight="bold")
    link(ax, (aft[0], aft[1] - 0.36), (aft[0], 2.74), BAD, lw=1.9)
    ax.text(14.5, 2.44, "\u2717 exits with NONE", ha="center", va="center",
            fontsize=13.5, color=BAD, fontweight="bold")

    ax.text(12.45, 1.44, "`break` is an EDGE, and \u201cafter the loop\u201d is a block it\n"
            "reaches. One of the two ways out of this function leaves\n"
            "with no value \u2014 which is the diagnosis, read off the graph.",
            ha="center", va="center", fontsize=14.5, color=TEXT)
    ax.text(12.45, 0.42, "\u2713  is that block reachable? one query", ha="center",
            va="center", fontsize=16, fontweight="bold", color=GOOD, family="monospace")

    ax.set_title("The same function, two data structures \u2014 and only one of them "
                 "records where a jump goes",
                 fontsize=18, color=TEXT, pad=16)
    fig.tight_layout()
    out = os.path.join(HERE, "break.png")
    fig.savefig(out, dpi=165, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_twopass()
    make_break()
