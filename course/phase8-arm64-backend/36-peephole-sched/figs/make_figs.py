#!/usr/bin/env python3
"""figs/peephole.png — the peephole pass: within a basic block, track which register holds each
slot, and forward a reload to a register move (or drop it). Honest note: this is LOCAL cleanup; the
cross-block variable reloads (the big cost) need mem2reg, not a peephole."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.6):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.03,rounding_size=0.05",
                 linewidth=1.2, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.30
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=9.0, fontweight="bold", color=TEXT, zorder=4); ty -= 0.40
    for ln in lines:
        col = "#a14a00" if ln.startswith("- ") else ("#2a7" if ln.startswith("+ ") else TEXT)
        ax.text(x + 0.18, ty, ln, ha="left", fontsize=fs, family="monospace", color=col, zorder=4); ty -= 0.33


def make():
    fig, ax = plt.subplots(figsize=(12.6, 6.2))
    ax.set_xlim(0, 13); ax.set_ylim(0, 7); ax.axis("off")
    ax.text(6.5, 6.7, "Peephole: forward a redundant memory load to a register move (local, within a block)",
            ha="center", fontsize=11.6, fontweight="bold", color=TEXT)

    box(ax, 0.3, 3.4, 4.3, 3.0,
        ["str  x19, [sp, #24]", "...", "ldr  x20, [sp, #24]   ; reload",
         "...", "ldr  x19, [sp, #24]   ; reload"],
        "#eef2f7", title="before (memory traffic)")
    box(ax, 5.0, 3.4, 4.3, 3.0,
        ["str  x19, [sp, #24]", "...", "+ mov  x20, x19     ; was a ldr", "...",
         "- (dropped)         ; x19 already holds it"],
        "#e8f6ee", title="after (peephole)")
    arr = FancyArrowPatch((4.6, 4.9), (5.0, 4.9), arrowstyle="-|>", mutation_scale=14, linewidth=1.8, color="#b5651d", zorder=5)
    ax.add_patch(arr)
    ax.text(4.8, 5.2, "slot->reg\ntable", ha="center", fontsize=8, color="#b5651d", fontweight="bold")

    box(ax, 9.7, 3.4, 3.0, 3.0,
        ["track held[(b,o)]", "= the reg holding", "  that slot.", "",
         "invalidate on:", "- reg overwritten", "- bl (clobbers)", "reset at each block"],
        "#fff8e1", title="the rule", fs=8.0)

    box(ax, 0.3, 0.5, 12.4, 2.5,
        ["What peephole removes: LOCAL redundancy -- a reload of a value already in a register.",
         "Measured: straight-line loads 18 -> 11 (the rest become movs the CPU renames away).",
         "",
         "What it CAN'T remove: a variable reloaded at the TOP of every block (it lives in alloc_stack",
         "memory) -- that is CROSS-block redundancy, the job of mem2reg/SSA promotion, not a peephole.",
         "And instruction SCHEDULING (reordering) is ~free on out-of-order cores. Match pass to redundancy."],
        "#f3e8fb", title="honest scope: local cleanup, not the structural fix")

    fig.tight_layout()
    out = os.path.join(HERE, "peephole.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
