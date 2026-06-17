#!/usr/bin/env python3
"""figs/macros.png — macros are an AST->AST rewrite that runs BEFORE the type checker. #line becomes
an integer literal; #assert becomes a conditional trap. Everything downstream (sema, SILGen, the
backends) sees only the expansion — ordinary code it checks and lowers as usual."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.4):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.03,rounding_size=0.05",
                 linewidth=1.2, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.28
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=8.8, fontweight="bold", color=TEXT, zorder=4); ty -= 0.40
    for ln in lines:
        ax.text(x + 0.16, ty, ln, ha="left", fontsize=fs, family="monospace", color=TEXT, zorder=4); ty -= 0.32


def arr(ax, p0, p1, color="#b5651d", label=None):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.8, color=color, zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + 0.16, label, ha="center", fontsize=7.8, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(13.0, 5.4)); ax.set_xlim(0, 13); ax.set_ylim(0, 5.6); ax.axis("off")
    ax.text(6.5, 5.3, "Macros: an AST -> AST rewrite that runs BEFORE the type checker",
            ha="center", fontsize=11.6, fontweight="bold", color=TEXT)

    box(ax, 0.3, 2.6, 3.3, 2.2,
        ["print(#line)", "", "#assert(x > 0)"],
        "#eef2f7", title="source (with macros)", fs=8.4)
    box(ax, 4.4, 2.6, 3.6, 2.2,
        ["print(1)        <- #line", "", "if x > 0 { }", "else { fatalError() }   <- #assert"],
        "#e8f6ee", title="after expansion (ordinary AST)", fs=8.0)
    box(ax, 8.6, 2.6, 4.1, 2.2,
        ["sema type-checks it", "SILGen lowers it", "Backend A (LLVM) /", "Backend B (ARM64) emit it"],
        "#dceede", title="the rest of the compiler", fs=8.2)
    arr(ax, (3.6, 3.7), (4.4, 3.7), label="expand")
    arr(ax, (8.0, 3.7), (8.6, 3.7), label="check + lower")

    box(ax, 1.5, 0.4, 10.0, 1.8,
        ["The expander walks the AST replacing each macro node with the code it stands for, then hands",
         "the result to sema -- so NOTHING downstream ever sees a macro, only ordinary code it checks.",
         "#line / #column -> integer literals (the source location).   #assert(c) -> if c {} else { trap }.",
         "Real macro systems also let USERS define macros (a plugin returning generated syntax) -- same model."],
        "#fff8e1", title="the principle: expand early, check the expansion", fs=8.0)

    fig.tight_layout()
    out = os.path.join(HERE, "macros.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
