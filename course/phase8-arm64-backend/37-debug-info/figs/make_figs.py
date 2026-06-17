#!/usr/bin/env python3
"""figs/debuginfo.png — source line numbers threaded end-to-end: SILGen stamps each value with its
statement's line; isel emits a .loc when the line changes; the assembler builds a DWARF line table
(address -> source line); lldb follows it to set breakpoints by line and step."""
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
        ax.text(x + w / 2, ty, title, ha="center", fontsize=8.7, fontweight="bold", color=TEXT, zorder=4); ty -= 0.38
    for ln in lines:
        ax.text(x + 0.16, ty, ln, ha="left", fontsize=fs, family="monospace", color=TEXT, zorder=4); ty -= 0.31


def arr(ax, p0, p1, label=None):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.7, color="#b5651d", zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + 0.16, label, ha="center", fontsize=7.8, color="#b5651d", fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(13.0, 5.6))
    ax.set_xlim(0, 13); ax.set_ylim(0, 6); ax.axis("off")
    ax.text(6.5, 5.7, "Debug info: a source line, threaded all the way to a DWARF line table lldb can step",
            ha="center", fontsize=11.4, fontweight="bold", color=TEXT)

    box(ax, 0.2, 2.7, 2.7, 2.6,
        ["1 func square(n):", "2   let r = n*n", "3   return r", "...", "6 let b = square(a)"],
        "#eef2f7", title="source (.swift)", fs=8.0)
    box(ax, 3.2, 2.7, 2.7, 2.6,
        ["SILGen stamps", "each value with", "its statement's", "line:", "lines[%v] = 2"],
        "#e8f6ee", title="SIL  (lines map)", fs=8.0)
    box(ax, 6.2, 2.7, 2.9, 2.6,
        ["emit .loc when", "the line changes:", "  .loc 1 2 0", "  mul x.., ..", "  .loc 1 3 0"],
        "#fff8e1", title="isel  (.loc dirs)", fs=8.0)
    box(ax, 9.4, 2.7, 3.4, 2.6,
        ["clang -g assembles", ".loc -> DWARF:", "addr 0x24 -> line 2", "addr 0x30 -> line 3",
         "addr 0x70 -> line 5"],
        "#dceede", title="DWARF .debug_line", fs=8.0)
    arr(ax, (2.9, 4.0), (3.2, 4.0))
    arr(ax, (5.9, 4.0), (6.2, 4.0))
    arr(ax, (9.1, 4.0), (9.4, 4.0))

    box(ax, 1.5, 0.4, 10.0, 1.9,
        ["(lldb) breakpoint set --file square.swift --line 3",
         "(lldb) run        -> Process stopped at square.swift:3",
         "(lldb) step       -> the debugger follows the line table through OUR machine code.",
         "macOS keeps the DWARF in the .o + a debug map in the exe -- we keep the .o so lldb resolves it."],
        "#e6dcf5", title="lldb steps a swiftml-built binary by source line", fs=8.4)

    fig.tight_layout()
    out = os.path.join(HERE, "debuginfo.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
