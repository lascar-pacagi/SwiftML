#!/usr/bin/env python3
"""figs/isel.png — the v0 stack machine: each SIL value gets a frame slot; a binop lowers to
load-operands-into-scratch, compute, store-result-back. Two backends (LLVM + our ARM64) share one
front end. Concept 34's register allocator is what removes the load/store traffic."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"
SIL = "#eef2f7"; ASM = "#dceede"; FR = "#fff3d6"; A = "#e6dcf5"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.6, mono=True):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.05",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.30
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=9.0, fontweight="bold", color=TEXT, zorder=4)
        ty -= 0.42
    fam = "monospace" if mono else "sans-serif"
    for ln in lines:
        ax.text(x + 0.22, ty, ln, ha="left", fontsize=fs, family=fam, color=TEXT, zorder=4)
        ty -= 0.345


def arr(ax, p0, p1, color="#b5651d", label=None, dx=0, dy=0.12):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.7,
                 color=color, zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center",
                fontsize=8.2, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(12.6, 6.8))
    ax.set_xlim(0, 13); ax.set_ylim(0, 7.2); ax.axis("off")
    ax.text(6.5, 6.95, "Instruction selection v0 — a stack machine: every SIL value lives in a frame slot",
            ha="center", fontsize=11.5, fontweight="bold", color=TEXT)

    # SIL (memory-based)
    box(ax, 0.3, 3.5, 3.1, 2.7,
        ["%9  = load %a", "%10 = load %b", "%11 = binop add", "        %9, %10", "store %11 -> %c"],
        SIL, title="SIL (memory-based)", fs=8.2)

    # frame
    box(ax, 4.0, 3.4, 2.7, 2.9,
        ["[sp,#0]   printf arg", "[sp,#16]  %a", "[sp,#24]  %b", "...", "[sp,#F-16] x29/x30"],
        FR, title="stack frame", fs=8.0)

    # ARM64 (one template per op)
    box(ax, 7.3, 3.3, 5.4, 3.0,
        ["ldr  x9,  [sp, #off_a]   ; load operand", "ldr  x10, [sp, #off_b]",
         "add  x9,  x9, x10        ; compute", "str  x9,  [sp, #off_c]   ; store back"],
        ASM, title="ARM64 (Backend B)", fs=8.0)
    arr(ax, (3.4, 4.8), (4.0, 4.8), label="slot per value")
    arr(ax, (6.7, 4.8), (7.3, 4.8), label="one template / op")

    # two backends
    box(ax, 0.3, 0.45, 5.6, 2.2,
        ["front end (lex/parse/sema/SILGen)", "  -> SIL -> SIL optimizer", "",
         "Backend A:  SIL -> IRGen -> LLVM -> clang",
         "Backend B:  SIL -> isel  -> ARM64 -> as/ld  <- THIS"],
        A, title="one front end, two backends", fs=8.0)
    box(ax, 6.4, 0.45, 6.3, 2.2,
        ["the load/store traffic is the cost —", "everything spills to the frame.", "",
         "concept 34's register allocator keeps values",
         "in x0..x28, and the loads/stores vanish."],
        SIL, title="why it's slow (and what 34 fixes)", fs=8.0)

    fig.tight_layout()
    out = os.path.join(HERE, "isel.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
