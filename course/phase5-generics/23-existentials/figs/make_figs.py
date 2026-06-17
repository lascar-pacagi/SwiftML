#!/usr/bin/env python3
"""Figures for 23-existentials/explainer.qmd.

    .venv/bin/python phase5-generics/23-existentials/figs/make_figs.py

Produces:
    figs/container.png — the fixed-size existential container: small conformers live INLINE in
    the 3-word buffer; large ones are heap-BOXED with the buffer holding the pointer. Same
    static type, two layouts — resolved per concrete type, not per protocol.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
BUF = "#fff3d6"
TBL = "#dceede"
HEAP = "#f3d6d6"


def cell(ax, x, y, w, h, txt, color, fs=8.6):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.04",
                 linewidth=1.2, edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x + w / 2, y + h / 2, txt, ha="center", va="center", fontsize=fs, family="monospace", color=TEXT, zorder=4)


def arr(ax, p0, p1, label=None, dx=0, dy=0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.6, color="#b5651d", zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center", fontsize=8.4,
                color="#b5651d", fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(11.4, 5.6))
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 6.4)
    ax.axis("off")

    # inline case
    ax.text(3.0, 5.9, "Circle(r:2)  —  1 word: fits INLINE", ha="center", fontsize=10.5, fontweight="bold", color=TEXT)
    cell(ax, 0.7, 4.4, 1.5, 0.9, "r = 2", BUF)
    cell(ax, 2.2, 4.4, 1.5, 0.9, "—", BUF)
    cell(ax, 3.7, 4.4, 1.5, 0.9, "—", BUF)
    cell(ax, 5.2, 4.4, 1.7, 0.9, "wt.Shape.\nCircle", TBL, fs=7.6)
    ax.text(3.0, 4.05, "[3 x i64] buffer              table ptr", ha="center", fontsize=8, color="#777")

    # boxed case
    ax.text(3.0, 2.9, "Big(a..e)  —  5 words: heap-BOXED", ha="center", fontsize=10.5, fontweight="bold", color=TEXT)
    cell(ax, 0.7, 1.4, 1.5, 0.9, "box ptr ►", BUF)
    cell(ax, 2.2, 1.4, 1.5, 0.9, "—", BUF)
    cell(ax, 3.7, 1.4, 1.5, 0.9, "—", BUF)
    cell(ax, 5.2, 1.4, 1.7, 0.9, "wt.Shape.\nBig", TBL, fs=7.6)
    # the heap box
    for i, t in enumerate(["a", "b", "c", "d", "e"]):
        cell(ax, 8.6 + i * 0.82, 1.4, 0.8, 0.9, t, HEAP)
    ax.text(10.6, 0.95, "malloc'd payload (the BOX)", ha="center", fontsize=8, color="#777")
    arr(ax, (2.1, 1.85), (8.55, 1.85), label="indirection — paid only by big types", dx=0, dy=0.32)

    ax.text(6.5, 6.3, "", ha="center")
    ax.text(9.6, 5.4, "Fixed container = separate compilation:\na NEW conformer in another module\nstill fits the SAME layout.\n(swiftc's exact design; whole-module\nmax-sizing can't do that.)",
            ha="center", fontsize=9, color="#444", style="italic")
    fig.suptitle("The existential container: 3 inline words + the witness table — small values inline, big values boxed",
                 fontsize=12, fontweight="bold", color=TEXT, y=0.02)
    out = os.path.join(HERE, "container.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
