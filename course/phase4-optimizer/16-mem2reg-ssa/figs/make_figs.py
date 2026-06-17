#!/usr/bin/env python3
"""Figures for 16-mem2reg-ssa/explainer.qmd.

    .venv/bin/python phase4-optimizer/16-mem2reg-ssa/figs/make_figs.py

Produces:
    figs/mem2reg.png — mem2reg on a loop: the raw memory form (alloc_stack/load/store) becomes
    SSA, where the loop-carried values are basic-block ARGUMENTS at the header (the "phi"), fed
    by the entry edge and the back-edge.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
MEM = "#eef2f7"
SSA = "#dceede"
PHI = "#ffe0c2"


def block(ax, x, y, lines, color, w=3.4, h=1.5, hot=False):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.03,rounding_size=0.06",
                 linewidth=(2.0 if hot else 1.3), edgecolor=("#b5651d" if hot else EDGE), facecolor=color, zorder=3))
    ax.text(x, y, "\n".join(lines), ha="center", va="center", fontsize=8.0, family="monospace", color=TEXT, zorder=4)


def arr(ax, p0, p1, color=EDGE, label=None, dx=0, dy=0, rad=0.0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.5, color=color,
                 zorder=2, connectionstyle=f"arc3,rad={rad}"))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center", fontsize=8, color=color, fontweight="bold", zorder=5)


def make():
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(12.2, 6.6))
    for ax in (a1, a2):
        ax.set_xlim(0, 6)
        ax.set_ylim(0, 9)
        ax.axis("off")

    # ---- left: raw, memory-based ----
    a1.set_title("RAW SIL — values live in stack slots", fontsize=12, color=TEXT, fontweight="bold")
    block(a1, 3, 7.7, ["bb0:", "s_slot = alloc; i_slot = alloc", "store 0->s; store 0->i"], MEM)
    block(a1, 3, 5.6, ["bb1 (header):", "s = load s_slot; i = load i_slot", "if i < n ..."], MEM)
    block(a1, 3, 3.5, ["bb2 (body):", "store (s+i) -> s_slot"], MEM)
    block(a1, 3, 1.5, ["bb3 (latch):", "store (i+1) -> i_slot", "-> bb1"], MEM)
    for (y0, y1) in [(6.95, 6.35), (4.85, 4.25), (2.75, 2.25)]:
        arr(a1, (3, y0), (3, y1))
    arr(a1, (4.7, 1.5), (4.7, 5.6), EDGE, "back-edge\n(load/store)", dx=0.7, rad=-0.5)

    # ---- right: SSA with block arguments ----
    a2.set_title("SSA after mem2reg — block arguments (the phi)", fontsize=12, color=TEXT, fontweight="bold")
    block(a2, 3, 7.7, ["bb0:", "br bb1(0, 0)"], SSA)
    block(a2, 3, 5.6, ["bb1(i, s):   <- the phi", "if i < n ..."], PHI, hot=True)
    block(a2, 3, 3.5, ["bb2:", "s' = s + i"], SSA)
    block(a2, 3, 1.5, ["bb3:", "i' = i + 1", "br bb1(i', s')"], SSA)
    arr(a2, (3, 6.95), (3, 6.35), "#2f6f4f", "(0, 0)", dx=0.75)
    arr(a2, (3, 4.85), (3, 4.25))
    arr(a2, (3, 2.75), (3, 2.25))
    arr(a2, (4.7, 1.5), (4.7, 5.6), "#2f6f4f", "(i', s')", dx=0.75, rad=-0.5)

    fig.suptitle("mem2reg: promote stack slots to SSA. A loop-carried value becomes a block ARGUMENT,\n"
                 "fed by the entry edge and the back-edge — no more load/store.",
                 fontsize=12.5, color=TEXT, y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.92])
    out = os.path.join(HERE, "mem2reg.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
