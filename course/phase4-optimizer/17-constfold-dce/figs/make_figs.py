#!/usr/bin/env python3
"""Figures for 17-constfold-dce/explainer.qmd.

    .venv/bin/python phase4-optimizer/17-constfold-dce/figs/make_figs.py

Produces:
    figs/branch_fold.png — on SSA, `3 < 5` folds to `true`, so a conditional branch becomes
    unconditional and the `else` block becomes unreachable and is deleted.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
BLK = "#eef2f7"
LIVE = "#dceede"
DEAD = "#f3d6d6"
T = "#2f6f4f"
F = "#b5651d"


def box(ax, x, y, lines, color, w=2.7, h=1.0, dead=False):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.03,rounding_size=0.06",
                 linewidth=1.3, edgecolor=("#c06", ) if False else EDGE, facecolor=color, zorder=3,
                 linestyle=("--" if dead else "-")))
    ax.text(x, y, "\n".join(lines), ha="center", va="center", fontsize=8.5, family="monospace",
            color=("#bbb" if dead else TEXT), zorder=4)


def arr(ax, p0, p1, color=EDGE, label=None, dx=0, dy=0, dead=False):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.5, color=color,
                 zorder=2, linestyle=("--" if dead else "-")))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center", fontsize=8.5,
                color=color, fontweight="bold", zorder=5)


def make():
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(11.6, 5.6))
    for ax in (a1, a2):
        ax.set_xlim(0, 6)
        ax.set_ylim(0, 7)
        ax.axis("off")

    a1.set_title("after constant folding: cond is `true`", fontsize=11.5, color=TEXT, fontweight="bold")
    box(a1, 3, 6.0, ["bb0:", "%c = true", "cond_br %c, bb1, bb2"], BLK)
    box(a1, 1.5, 3.5, ["bb1:", "print(1)"], LIVE)
    box(a1, 4.5, 3.5, ["bb2:", "print(2)"], BLK)
    box(a1, 3, 1.2, ["bb3: …"], BLK)
    arr(a1, (2.3, 5.6), (1.7, 4.1), T, "true", dx=-0.35)
    arr(a1, (3.7, 5.6), (4.3, 4.1), F, "false", dx=0.4)
    arr(a1, (1.5, 3.0), (2.6, 1.6))
    arr(a1, (4.5, 3.0), (3.4, 1.6))

    a2.set_title("simplify-cfg: fold the branch, delete the dead block", fontsize=11.5, color=TEXT, fontweight="bold")
    box(a2, 3, 6.0, ["bb0:", "br bb1"], LIVE)
    box(a2, 1.5, 3.5, ["bb1:", "print(1)"], LIVE)
    box(a2, 4.5, 3.5, ["bb2:", "print(2)"], DEAD, dead=True)
    box(a2, 3, 1.2, ["bb3: …"], LIVE)
    arr(a2, (2.6, 5.5), (1.7, 4.1), T)
    arr(a2, (4.3, 4.1), (3.7, 5.5), DEAD[:-1] and "#c99", dead=True)
    arr(a2, (1.5, 3.0), (2.6, 1.6))
    a2.text(4.5, 2.5, "unreachable\n→ deleted", ha="center", fontsize=8.5, color="#b22", fontstyle="italic")

    fig.suptitle("On SSA, constant folding reaches the condition — so the branch and a whole block disappear",
                 fontsize=12.5, color=TEXT, y=0.98)
    fig.tight_layout(rect=[0, 0, 1, 0.93])
    out = os.path.join(HERE, "branch_fold.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
