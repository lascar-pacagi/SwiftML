#!/usr/bin/env python3
"""figs/ladder.png — the register-allocation ladder. Left: the idea (vregs -> physical, spill the
interval ending latest / colour the interference graph). Right: measured runtimes — each rung beats
the last, graph-colour ~2.9x over stack, approaching the LLVM -O path. Numbers from bench/ (best of
3, hotloop/collatz/fibloop)."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"

# measured (seconds, best of 3) — see bench/
BENCH = {
    "hotloop": {"stack": 0.126, "linscan": 0.030, "graphcolor": 0.029, "llvm": 0.013},
    "collatz": {"stack": 0.301, "linscan": 0.129, "graphcolor": 0.131, "llvm": 0.036},
    "fibloop": {"stack": 0.025, "linscan": 0.010, "graphcolor": 0.010, "llvm": 0.002},
}
RUNGS = ["stack", "linscan", "graphcolor", "llvm"]
COLORS = {"stack": "#d98880", "linscan": "#f7dc6f", "graphcolor": "#7dcea0", "llvm": "#aed6f1"}
LABELS = {"stack": "v0 stack", "linscan": "v1 linscan", "graphcolor": "v2 graph-colour", "llvm": "(LLVM -O)"}


def box(ax, x, y, w, h, lines, color, title=None, fs=8.4):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.05",
                 linewidth=1.2, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.30
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=8.8, fontweight="bold", color=TEXT, zorder=4); ty -= 0.40
    for ln in lines:
        ax.text(x + 0.18, ty, ln, ha="left", fontsize=fs, family="monospace", color=TEXT, zorder=4); ty -= 0.33


def make():
    fig, (axL, axR) = plt.subplots(1, 2, figsize=(13.2, 5.6), gridspec_kw={"width_ratios": [1.05, 1.0]})
    fig.suptitle("Register allocation: the ladder — spill everything, then keep values in registers",
                 fontsize=12.5, fontweight="bold", color=TEXT, y=0.99)

    # --- left: the idea ---
    axL.set_xlim(0, 10); axL.set_ylim(0, 10); axL.axis("off")
    box(axL, 0.3, 7.4, 9.3, 2.2,
        ["each SIL value -> a virtual register (Virt v)",
         "allocate -> physical x19..x27 (callee-saved: survive calls)",
         "or SPILL -> the value's frame slot [sp,#16+8v]"],
        "#eef2f7", title="isel emits vregs; regalloc places them")
    box(axL, 0.3, 4.3, 4.5, 2.7,
        ["sort intervals by start", "walk; a free reg -> take it", "no reg free -> spill the",
         "  interval ending LATEST", "(it frees a reg for longest)"],
        "#fff8e1", title="v1 linear-scan")
    box(axL, 5.1, 4.3, 4.5, 2.7,
        ["vregs whose live ranges", "overlap INTERFERE.", "simplify: pop deg<K nodes;",
         "select: colour each with a", "reg no neighbour took."],
        "#e8f6ee", title="v2 graph-colour (Chaitin-Briggs)")
    box(axL, 0.3, 1.2, 9.3, 2.6,
        ["pool = x19..x27 (9 callee-saved) -> any allocated value is call-safe for free.",
         "x9..x14 = scratch for spilled operands. a 'spill' = live in your own slot.",
         "v0 stack = spill ALL (concept 33). the frame's prologue saves the callee-saved it used.",
         "honest gap to LLVM: our variables stay in alloc_stack memory (mem2reg would promote them)."],
        "#f3e8fb", title="the rules that make it simple")

    # --- right: the measured bars ---
    names = list(BENCH.keys())
    nb = len(names); nr = len(RUNGS)
    bw = 0.2
    import numpy as np
    xs = np.arange(nb)
    for j, rung in enumerate(RUNGS):
        vals = [BENCH[n][rung] for n in names]
        axR.bar(xs + (j - 1.5) * bw, vals, bw, label=LABELS[rung], color=COLORS[rung], edgecolor=EDGE, linewidth=0.7)
    axR.set_xticks(xs); axR.set_xticklabels(names, fontsize=9)
    axR.set_ylabel("runtime (s, best of 3 — lower is better)", fontsize=9)
    axR.set_title("each rung beats the last; graph-colour ~2.9x over stack (geomean)", fontsize=9.6, color=TEXT)
    axR.legend(fontsize=8, loc="upper right")
    axR.grid(axis="y", linestyle=":", alpha=0.5)
    for spine in ["top", "right"]:
        axR.spines[spine].set_visible(False)

    fig.tight_layout(rect=[0, 0, 1, 0.96])
    out = os.path.join(HERE, "ladder.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
