#!/usr/bin/env python3
"""Figures for 06-control-flow/explainer.qmd.

    .venv/bin/python phase2-types-flow/06-control-flow/figs/make_figs.py

Produces:
    figs/cfg.png — a while loop as a control-flow graph (basic blocks + branches). The
    AST is a tree, but control flow is a *graph* — which is exactly why SIL (concept 08)
    represents a function as basic blocks joined by branch edges.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
BLK = "#eef2f7"
COND = "#fff3d6"
EDGE = "#5b6b7b"
TEXT = "#1b2733"
TRUE = "#2f6f4f"
FALSE = "#b5651d"


def block(ax, x, y, w, h, lines, color):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h,
                 boxstyle="round,pad=0.03,rounding_size=0.08", linewidth=1.3,
                 edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y, "\n".join(lines), ha="center", va="center", fontsize=10.5,
            family="monospace", color=TEXT, zorder=4)


def arrow(ax, p0, p1, color=EDGE, rad=0.0, label=None, lx=0, ly=0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=14, linewidth=1.5,
                 color=color, zorder=2, connectionstyle=f"arc3,rad={rad}"))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + lx, (p0[1] + p1[1]) / 2 + ly, label, ha="center",
                va="center", fontsize=9.5, color=color, fontweight="bold", zorder=5)


def make_cfg():
    fig, ax = plt.subplots(figsize=(8.6, 6.0))
    ax.set_xlim(0, 9)
    ax.set_ylim(0, 6.4)
    ax.axis("off")

    entry = (3.0, 5.6)
    header = (3.0, 4.0)
    body = (3.0, 2.0)
    after = (7.0, 4.0)

    block(ax, *entry, 3.4, 0.8, ["entry:", "var n = 0"], BLK)
    block(ax, *header, 3.4, 0.9, ["header:", "n < 5 ?"], COND)
    block(ax, *body, 3.4, 0.9, ["body:", "n = n + 1"], BLK)
    block(ax, *after, 3.2, 0.8, ["exit:", "print(n)"], BLK)

    arrow(ax, (entry[0], entry[1] - 0.4), (header[0], header[1] + 0.45))
    arrow(ax, (header[0], header[1] - 0.45), (body[0], body[1] + 0.45), TRUE, label="true", lx=-0.5)
    # back edge: body -> header
    arrow(ax, (body[0] + 1.7, body[1]), (header[0] + 1.7, header[1] - 0.3), EDGE, rad=-0.5,
          label="back edge", lx=1.35, ly=-0.2)
    # false -> exit
    arrow(ax, (header[0] + 1.7, header[1]), (after[0] - 1.6, after[1]), FALSE, label="false", ly=0.28)

    ax.set_title("A `while` loop is a control-flow GRAPH — basic blocks joined by branches\n"
                 "(the AST is a tree; this is why SIL, concept 08, uses basic blocks)",
                 fontsize=12, color=TEXT, pad=10)
    fig.tight_layout()
    out = os.path.join(HERE, "cfg.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_cfg()
