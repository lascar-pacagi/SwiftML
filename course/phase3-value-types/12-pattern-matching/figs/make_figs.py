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


def box(ax, x, y, lines, color, w=3.0, h=0.9, label=None):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.03,rounding_size=0.06",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    if label:                                   # the SIL block this box is, named as `--emit-sil` names it
        ax.text(x - w / 2 + 0.12, y + h / 2 - 0.17, label, ha="left", va="center", fontsize=9.5,
                family="monospace", color=EDGE, fontweight="bold", zorder=4)
        y -= 0.13
    ax.text(x, y, "\n".join(lines), ha="center", va="center", fontsize=10.5, family="monospace",
            color=TEXT, zorder=4)


def arrow(ax, p0, p1, color=EDGE, label=None, dx=0, dy=0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=13, linewidth=1.5, color=color, zorder=2))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center", fontsize=10,
                color=color, fontweight="bold", zorder=5)


def make_dispatch():
    fig, ax = plt.subplots(figsize=(11.4, 6.2))
    ax.set_xlim(0.2, 11.8)
    ax.set_ylim(0.25, 8.0)
    ax.axis("off")

    xt, xc, xr = 2.9, 8.2, 11.2
    ys = [6.3, 4.5, 2.7]
    box(ax, xt, 7.5, ["%t = enum_tag %s"], MERGE, w=3.8, h=0.8, label="bb0")
    arrow(ax, (xt, 7.1), (xt, ys[0] + 0.5))

    tests = ["%t == 0 ?", "%t == 1 ?", "%t == 2 ?"]
    cases = [["%r = enum_payload %s, #0", "…body…", "br merge"],
             ["%w,%h = #0, #1", "…body…", "br merge"],
             ["…body…", "br merge"]]
    labels = ["case .circle", "case .rect", "case .dot"]
    for i, y in enumerate(ys):
        box(ax, xt, y, [tests[i]], TEST, w=3.0, h=0.9, label="bb%d" % (i + 1))
        box(ax, xc, y, cases[i], CASE, w=4.6, h=1.3, label=labels[i])
        arrow(ax, (xt + 1.5, y), (xc - 2.3, y), T, "true", dy=0.25)
        if i < len(ys) - 1:
            arrow(ax, (xt, y - 0.45), (xt, ys[i + 1] + 0.45), F, "false", dx=-0.62)
        # every case branches to the MERGE, not to the next case — so the edges ride a rail on
        # the right instead of cutting through the blocks between them, which read as fallthrough
        ax.plot([xc + 2.3, xr], [y, y], color=EDGE, linewidth=1.5, zorder=1)
        ax.plot([xr, xr], [y, 1.05], color=EDGE, linewidth=1.5, zorder=1)
    arrow(ax, (xr, 1.05), (xc + 2.35, 1.05), EDGE)
    box(ax, xt, 1.05, ["unreachable"], MERGE, w=3.0, h=0.8)
    arrow(ax, (xt, ys[-1] - 0.45), (xt, 1.05 + 0.4), F, "false", dx=-0.68)
    box(ax, xc, 1.05, ["…after the switch…"], MERGE, w=4.6, h=0.8, label="merge")

    ax.set_title("Lowering `switch`: read the tag once, then a chain of tests — each case block\n"
                 "binds its payload and branches to the merge",
                 fontsize=13, color=TEXT, pad=10)
    fig.tight_layout()
    out = os.path.join(HERE, "dispatch.png")
    fig.savefig(out, dpi=170, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_dispatch()
