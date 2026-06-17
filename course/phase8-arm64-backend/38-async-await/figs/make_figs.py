#!/usr/bin/env python3
"""figs/async.png — async/await on a cooperative executor. Task { } lifts a coroutine + spawns it;
the executor round-robins ready tasks, resuming each at its yield; each task is a stackful coroutine
(its own stack via ucontext). The compiler emits runtime calls — zero new SIL."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.3):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.03,rounding_size=0.05",
                 linewidth=1.2, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.28
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=8.7, fontweight="bold", color=TEXT, zorder=4); ty -= 0.38
    for ln in lines:
        ax.text(x + 0.16, ty, ln, ha="left", fontsize=fs, family="monospace", color=TEXT, zorder=4); ty -= 0.31


def arr(ax, p0, p1, color="#b5651d", label=None, dy=0.13):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=11, linewidth=1.6, color=color, zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + dy, label, ha="center", fontsize=7.6, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(13.0, 6.0)); ax.set_xlim(0, 13); ax.set_ylim(0, 6.4); ax.axis("off")
    ax.text(6.5, 6.1, "async / await on a cooperative executor: tasks are coroutines the scheduler round-robins",
            ha="center", fontsize=11.4, fontweight="bold", color=TEXT)

    box(ax, 0.2, 3.5, 3.0, 2.3,
        ["Task { await", "       worker(1) }", "", "-> lift a coroutine", "-> rt_async_spawn"],
        "#e6dcf5", title="compiler (silgen)", fs=8.0)
    box(ax, 3.5, 3.5, 3.2, 2.3,
        ["ready queue (FIFO):", "  [task1, task2, task3]", "", "rt_async_run drains it,", "round-robin"],
        "#fff8e1", title="executor (runtime)", fs=8.0)
    box(ax, 7.0, 3.5, 5.8, 2.3,
        ["task1: print 11; YIELD ...resume... print 12; done",
         "task2: print 21; YIELD ...resume... print 22; done",
         "each task = a STACKFUL coroutine (own stack, ucontext)",
         "yield = swapcontext to the scheduler; resume = swap back"],
        "#dceede", title="coroutines suspend & resume", fs=7.7)
    arr(ax, (3.2, 4.6), (3.5, 4.6), label="spawn")
    arr(ax, (6.7, 4.6), (7.0, 4.6), label="run")

    box(ax, 1.0, 0.4, 11.0, 2.6,
        ["Output for 3 tasks each yielding twice (round-robin):  0  11 21 31  12 22 32  13 23 33",
         "",
         "Zero new SIL: async/await/Task lower to rt_async_spawn / rt_async_yield / rt_async_run.",
         "swiftc uses STACKLESS coroutines (CPS state machines) for efficiency; we use STACKFUL (a",
         "stack per task) for simplicity -- same observable semantics on a serial cooperative executor.",
         "(Swift's DEFAULT executor is concurrent/nondeterministic; ours is deterministic FIFO.)"],
        "#eef2f7", title="the model -- and the honest difference from swiftc", fs=8.0)

    fig.tight_layout()
    out = os.path.join(HERE, "async.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
