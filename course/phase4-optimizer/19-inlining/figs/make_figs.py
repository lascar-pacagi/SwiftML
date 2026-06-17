#!/usr/bin/env python3
"""Figures for 19-inlining/explainer.qmd.

    .venv/bin/python phase4-optimizer/19-inlining/figs/make_figs.py

Produces:
    figs/inline.png — inlining replaces a call with the callee's body, which then lets the
    OTHER passes (folding, here) work across the old boundary: sq(5) -> 5*5 -> 25.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
CALL = "#eef2f7"
INL = "#fff3d6"
DONE = "#dceede"


def box(ax, x, y, title, lines, color, w=3.2, h=2.0):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.04,rounding_size=0.06",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y + h / 2 - 0.3, title, ha="center", fontsize=10, fontweight="bold", color=TEXT, zorder=4)
    ax.text(x, y - 0.25, "\n".join(lines), ha="center", va="center", fontsize=8.5, family="monospace", color=TEXT, zorder=4)


def arr(ax, x0, x1, y, label):
    ax.add_patch(FancyArrowPatch((x0, y), (x1, y), arrowstyle="-|>", mutation_scale=15, linewidth=1.8, color="#b5651d", zorder=2))
    ax.text((x0 + x1) / 2, y + 0.45, label, ha="center", fontsize=9.5, fontweight="bold", color="#b5651d")


def make():
    fig, ax = plt.subplots(figsize=(12.0, 4.2))
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 4)
    ax.axis("off")

    box(ax, 2.2, 2.0, "a call", ["func sq(x):", "  return x*x", "", "main:", "  print(sq(5))"], CALL, h=2.6)
    arr(ax, 4.0, 5.6, 2.0, "inline")
    box(ax, 7.0, 2.0, "after inlining", ["main:", "  %m = 5 * 5", "  print(%m)", "", "(no call; sq removed)"], INL, h=2.6)
    arr(ax, 8.6, 10.4, 2.0, "fold\n(now visible)")
    box(ax, 11.8, 2.0, "after folding", ["main:", "  print(25)"], DONE, h=2.6)

    fig.suptitle("Inlining replaces a call with the callee's body — then the OTHER passes run across the old boundary",
                 fontsize=12.5, color=TEXT, y=0.99)
    fig.tight_layout(rect=[0, 0, 1, 0.9])
    out = os.path.join(HERE, "inline.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
