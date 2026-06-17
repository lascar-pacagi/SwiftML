#!/usr/bin/env python3
"""Figures for 12-pattern-matching/explainer.qmd.

    .venv/bin/python phase3-value-types/12-pattern-matching/figs/make_figs.py

Produces:
    figs/dispatch.png — how a `switch` over an enum compiles: read the tag, then a chain of
    `tag == k ?` tests, each branching to a case block that binds the payload, all converging
    on a merge block.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
TEST = "#fff3d6"
CASE = "#dceede"
MERGE = "#eef2f7"
T = "#2f6f4f"
F = "#b5651d"


def box(ax, x, y, lines, color, w=3.0, h=0.9):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.03,rounding_size=0.06",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y, "\n".join(lines), ha="center", va="center", fontsize=8.8, family="monospace", color=TEXT, zorder=4)


def arrow(ax, p0, p1, color=EDGE, label=None, dx=0, dy=0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.4, color=color, zorder=2))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center", fontsize=8.5,
                color=color, fontweight="bold", zorder=5)


def make_dispatch():
    fig, ax = plt.subplots(figsize=(10.6, 6.4))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 8.2)
    ax.axis("off")

    xt, xc, xm = 2.6, 7.6, 7.6
    ys = [6.6, 4.9, 3.2]
    box(ax, xt, 7.7, ["%t = enum_tag s"], MERGE, w=3.2, h=0.7)
    arrow(ax, (xt, 7.35), (xt, ys[0] + 0.45))

    tests = ["tag == 0 ?", "tag == 1 ?", "tag == 2 ?"]
    cases = [["case .circle:", "  bind r = payload#0", "  …body…"],
             ["case .rect:", "  bind w,h = #0,#1", "  …body…"],
             ["case .dot:", "  …body…"]]
    for i, y in enumerate(ys):
        box(ax, xt, y, [tests[i]], TEST, w=2.6, h=0.8)
        box(ax, xc, y, cases[i], CASE, w=3.6, h=1.1)
        arrow(ax, (xt + 1.3, y), (xc - 1.8, y), T, "true", dy=0.22)
        if i < len(ys) - 1:
            arrow(ax, (xt, y - 0.4), (xt, ys[i + 1] + 0.4), F, "false", dx=-0.55)
        arrow(ax, (xc, y - 0.55), (xm, 1.3 + 0.45), EDGE)
    # last false -> unreachable
    box(ax, xt, 1.6, ["unreachable"], MERGE, w=2.6, h=0.7)
    arrow(ax, (xt, ys[-1] - 0.4), (xt, 1.6 + 0.35), F, "false", dx=-0.6)
    box(ax, xm, 1.3, ["merge: …after the switch…"], MERGE, w=4.2, h=0.7)

    ax.set_title("Lowering `switch`: read the tag, then a dispatch chain — each case binds its payload, all join at a merge",
                 fontsize=12, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "dispatch.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_dispatch()
