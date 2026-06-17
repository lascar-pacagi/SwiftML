#!/usr/bin/env python3
"""Figures for course-map/explainer.qmd — the whole-course map.

    .venv/bin/python course-map/figs/make_figs.py

Produces:
    figs/pipeline.png       — the full pipeline (one front end, two backends), a tall centered
                              spine that splits orthogonally into the two backends.
    figs/phases.png         — the 8 phases as a ladder, with milestones M0..M8.
    figs/datastructures.png — the IRs that flow between stages (tokens -> AST -> SIL -> LLVM/ARM64).
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
STAGE = "#e8eef6"      # stage box
PASS = "#fff3d6"       # IR / data
BLLVM = "#dce9f7"      # backend A
BARM = "#e7e0f3"       # backend B
ACC = "#2f6f4f"
EDGE = "#5b6b7b"
TEXT = "#1b2733"
SUB = "#5b6b7b"


def box(ax, x, y, w, h, label, sub=None, fc=STAGE, fs=11.0, bold=True):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.012,rounding_size=0.02",
                                linewidth=1.2, edgecolor=EDGE, facecolor=fc, zorder=2))
    ax.text(x + w / 2, y + h * (0.62 if sub else 0.5), label, ha="center", va="center",
            fontsize=fs, color=TEXT, fontweight="bold" if bold else "normal", zorder=3)
    if sub:
        ax.text(x + w / 2, y + h * 0.26, sub, ha="center", va="center", fontsize=8.0, color=SUB, zorder=3)


def arrow(ax, x1, y1, x2, y2, color=EDGE, lw=1.7):
    ax.add_patch(FancyArrowPatch((x1, y1), (x2, y2), arrowstyle="-|>", mutation_scale=14,
                                 linewidth=lw, color=color, shrinkA=1, shrinkB=3, zorder=1))


def vline(ax, x, y1, y2, color=EDGE, lw=1.7):
    ax.plot([x, x], [y1, y2], color=color, linewidth=lw, solid_capstyle="round", zorder=1)


def hline(ax, x1, x2, y, color=EDGE, lw=1.7):
    ax.plot([x1, x2], [y, y], color=color, linewidth=lw, solid_capstyle="round", zorder=1)


def pipeline():
    # A tall, centered vertical spine (so it stays large when fit to page width) that splits with a
    # clean right-angle bus into the two backends. Every arrow is straight or orthogonal — no diagonals.
    fig, ax = plt.subplots(figsize=(10.0, 11.6))
    ax.set_xlim(0, 10.0); ax.set_ylim(0, 11.6); ax.axis("off")
    cx = 5.0
    ax.text(cx, 11.25, "The swiftml pipeline: one front end, two backends",
            ha="center", fontsize=16, fontweight="bold", color=TEXT)
    ax.text(cx, 10.85, "boxes = stages   grey = the concepts that build each one   "
            "the shared spine lowers to SIL, then splits", ha="center", fontsize=9.5, color=SUB)

    w = 4.4; h = 0.66; x = cx - w / 2
    spine = [
        ("Source .swift", "the program text", "#ffffff"),
        ("Lexer", "text to tokens   ::  01", STAGE),
        ("Parser", "tokens to AST (Pratt)   ::  02", STAGE),
        ("Sema", "type-check   ::  03, 05-07, 10-13, 21-23, 25, 30, 39", STAGE),
        ("SILGen", "AST to SIL   ::  08, 10-13, 25-32, 38-40", STAGE),
        ("raw SIL", "memory-based basic blocks (the hinge)", PASS),
        ("SIL optimizer  (-O)", "mem2reg 16 - fold 17 - GVN 18 - inline 19 - spec 24 - ARC 28", PASS),
    ]
    ys = [9.95 - i * 0.95 for i in range(len(spine))]
    for i, (name, sub, fc) in enumerate(spine):
        y = ys[i]
        box(ax, x, y, w, h, name, sub, fc=fc, fs=12.5)
        if i > 0:
            arrow(ax, cx, ys[i - 1], cx, y + h)

    oy = ys[-1]
    busy = oy - 0.62
    ax_col, bx_col = 2.55, 7.45
    vline(ax, cx, oy, busy)
    hline(ax, ax_col, bx_col, busy)
    # column headers sit ABOVE the bus (off to each side, clear of the centre line and the boxes)
    ax.text(ax_col, busy + 0.28, "Backend A: the LLVM spine", ha="center", fontsize=10.5,
            fontweight="bold", color=ACC)
    ax.text(bx_col, busy + 0.28, "Backend B: from-scratch ARM64", ha="center", fontsize=10.5,
            fontweight="bold", color=ACC)

    cw = 3.4; ch = 0.62
    colA = [("IRGen", "SIL to LLVM IR   ::  09"), ("LLVM / clang", "-O0 / -O2   ::  09, 20"),
            ("native exe", "x86 / arm64")]
    colB = [("ARM64 isel", "33"), ("regalloc", "the ladder   ::  34"),
            ("native exe", "+ ABI 35 - peephole 36 - DWARF 37")]
    yrow = [busy - 0.95 - j * 0.95 for j in range(3)]
    for col, ccx, fc in [(colA, ax_col, BLLVM), (colB, bx_col, BARM)]:
        for j, (name, sub) in enumerate(col):
            box(ax, ccx - cw / 2, yrow[j], cw, ch, name, sub, fc=fc, fs=11)
            if j > 0:
                arrow(ax, ccx, yrow[j - 1], ccx, yrow[j] + ch)
        arrow(ax, ccx, busy, ccx, yrow[0] + ch)

    fig.savefig(os.path.join(HERE, "pipeline.png"), dpi=165, bbox_inches="tight")
    plt.close(fig)


def phases():
    fig, ax = plt.subplots(figsize=(11.4, 7.4))
    ax.set_xlim(0, 11.4); ax.set_ylim(0, 7.4); ax.axis("off")
    ax.text(5.7, 7.1, "The build, phase by phase",
            ha="center", fontsize=15, fontweight="bold", color=TEXT)
    ax.text(5.7, 6.74, "each phase is a complete compiler for a bigger subset, proven against swiftc",
            ha="center", fontsize=9.6, color=SUB)
    rows = [
        ("Phase 0", "00", "bootstrap: one integer to a real arm64 exe", "M0"),
        ("Phase 1", "01-04", "minimal: lex - parse - sema - LLVM codegen", "M1"),
        ("Phase 2", "05-09", "types & control flow: inference, if/while/for, functions, SIL, run!", "M2"),
        ("Phase 3", "10-14", "value types: structs, enums, pattern matching, optionals, layout", "M3"),
        ("Phase 4", "15-20", "the optimizer: pass mgr, mem2reg/SSA, fold, GVN, inline, LLVM -O2", "M4"),
        ("Phase 5", "21-24", "generics & protocols: witnesses, generics, existentials, specialization", "M5"),
        ("Phase 6", "25-28", "classes & ARC: vtables, retain/release, ownership SSA, ARC-opt", "M6"),
        ("Phase 7", "29-32", "closures, errors, stdlib: Array/String CoW, map/filter/reduce", "M7"),
        ("Phase 8", "33-40", "ARM64 backend + tail: isel, regalloc, ABI, debug; async, actors, macros", "M8"),
    ]
    top = 6.05; rh = 0.58; gap = 0.07
    pal = ["#eef2f7", "#e9f0e9", "#e9f0e9", "#fdf0df", "#fdf0df", "#ece6f5", "#ece6f5", "#e2eef3", "#f3e7e7"]
    for i, (ph, cc, desc, mile) in enumerate(rows):
        y = top - i * (rh + gap)
        ax.add_patch(FancyBboxPatch((0.3, y), 9.3, rh, boxstyle="round,pad=0.01,rounding_size=0.02",
                                    linewidth=1.1, edgecolor=EDGE, facecolor=pal[i]))
        ax.text(0.5, y + rh / 2, ph, ha="left", va="center", fontsize=10.5, fontweight="bold", color=TEXT)
        ax.text(1.75, y + rh / 2, cc, ha="left", va="center", fontsize=9.5, color=ACC, fontweight="bold")
        ax.text(2.95, y + rh / 2, desc, ha="left", va="center", fontsize=9.0, color=TEXT)
        ax.add_patch(FancyBboxPatch((9.85, y + 0.06), 1.2, rh - 0.12,
                                    boxstyle="round,pad=0.01,rounding_size=0.03",
                                    linewidth=1.1, edgecolor=ACC, facecolor="#ffffff"))
        ax.text(10.45, y + rh / 2, mile, ha="center", va="center", fontsize=10, fontweight="bold", color=ACC)
    ax.text(10.45, top + rh + 0.02, "milestone", ha="center", fontsize=8.4, color=SUB)
    ax.text(0.3, 0.28, "Milestones M4/M5/M6/M8 are also measured: 129% / 104% / 126% of swiftc -O, "
            "and a regalloc ladder ~2.9x over naive.", ha="left", fontsize=9, color=SUB)
    fig.savefig(os.path.join(HERE, "phases.png"), dpi=165, bbox_inches="tight")
    plt.close(fig)


def datastructures():
    fig, ax = plt.subplots(figsize=(13.6, 4.7))
    ax.set_xlim(0, 13.6); ax.set_ylim(0, 4.7); ax.axis("off")
    ax.text(6.0, 4.45, "The intermediate representations that flow through the compiler",
            ha="center", fontsize=13, fontweight="bold", color=TEXT)
    # linear chain (shared front end + SIL)
    chain = [
        (".swift\nsource", "#ffffff", "text"),
        ("tokens", PASS, "Lexer 01"),
        ("AST", PASS, "Parser 02"),
        ("typed AST", PASS, "Sema 03+"),
        ("SIL", "#fff3d6", "SILGen 08"),
        ("SSA SIL", "#ffe3b0", "mem2reg 16"),
    ]
    w = 1.45; gap = 0.40; x0 = 0.3; y = 1.9; h = 0.95
    xs = []
    for i, (lbl, fc, sub) in enumerate(chain):
        xx = x0 + i * (w + gap)
        box(ax, xx, y, w, h, lbl, sub, fc=fc, fs=10.5)
        xs.append(xx)
        if i > 0:
            arrow(ax, xs[i - 1] + w, y + h / 2, xx, y + h / 2)
    # the split from SSA SIL into the two backends (stacked right, clean orthogonal bracket)
    sx = xs[-1] + w
    bw = 1.7; bx = sx + 0.85
    box(ax, bx, y + 1.05, bw, h, "LLVM IR", "IRGen 09 (Backend A)", fc=BLLVM, fs=10.5)
    box(ax, bx, y - 1.05, bw, h, "ARM64 asm", "isel 33 (Backend B)", fc=BARM, fs=10.5)
    midx = (sx + bx) / 2
    hline(ax, sx, midx, y + h / 2)
    vline(ax, midx, y + 1.05 + h / 2, y - 1.05 + h / 2)
    arrow(ax, midx, y + 1.05 + h / 2, bx, y + 1.05 + h / 2)
    arrow(ax, midx, y - 1.05 + h / 2, bx, y - 1.05 + h / 2)
    fig.savefig(os.path.join(HERE, "datastructures.png"), dpi=165, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    pipeline()
    phases()
    datastructures()
    print("wrote pipeline.png, phases.png, datastructures.png")
