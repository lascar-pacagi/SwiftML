#!/usr/bin/env python3
"""Figures for 15-pass-manager/explainer.qmd.

    .venv/bin/python phase4-optimizer/15-pass-manager/figs/make_figs.py

Produces:
    figs/pipeline.png — the SIL optimizer is a PIPELINE of passes (each Sil.func -> Sil.func)
    run by the pass manager. A before/after of `print(1 + 2 * 3)`: constant-fold turns the
    arithmetic into a literal, then DCE deletes the now-dead instructions.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
SIL = "#eef2f7"
PASS = "#fff3d6"
HL = "#dceede"


def codebox(ax, x, y, title, lines, color, w=4.2, h=2.6):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.04,rounding_size=0.06",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y + h / 2 - 0.28, title, ha="center", fontsize=10.5, fontweight="bold", color=TEXT, zorder=4)
    ax.text(x, y - 0.2, "\n".join(lines), ha="center", va="center", fontsize=8.3, family="monospace", color=TEXT, zorder=4)


def passbox(ax, x, y, label):
    ax.add_patch(FancyBboxPatch((x - 1.35, y - 0.42), 2.7, 0.84, boxstyle="round,pad=0.03,rounding_size=0.1",
                 linewidth=1.3, edgecolor=EDGE, facecolor=PASS, zorder=3))
    ax.text(x, y, label, ha="center", va="center", fontsize=9.5, family="monospace", fontweight="bold", color=TEXT, zorder=4)


def arrow(ax, p0, p1):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=14, linewidth=1.6, color=EDGE, zorder=2))


def make_pipeline():
    fig, ax = plt.subplots(figsize=(11.4, 6.2))
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 7)
    ax.axis("off")

    # the pass manager pipeline (top)
    ax.text(6.5, 6.6, "The pass manager runs a pipeline of passes (each  Sil.func -> Sil.func),  driven by  -O",
            ha="center", fontsize=11.5, color=TEXT, fontweight="bold")
    passbox(ax, 4.0, 5.6, "constant-fold")
    passbox(ax, 9.0, 5.6, "dead-instr-elim")
    arrow(ax, (1.6, 5.6), (2.6, 5.6))
    arrow(ax, (5.4, 5.6), (7.6, 5.6))
    arrow(ax, (10.4, 5.6), (11.4, 5.6))
    ax.text(0.9, 5.6, "raw\nSIL", ha="center", va="center", fontsize=9, color=TEXT)
    ax.text(12.1, 5.6, "opt'd\nSIL", ha="center", va="center", fontsize=9, color=TEXT)

    # before / after of print(1 + 2 * 3)
    codebox(ax, 3.2, 2.4, "raw SIL  (print(1 + 2 * 3))",
            ["%0 = integer_literal 1", "%1 = integer_literal 2",
             "%2 = integer_literal 3", "%3 = binop \"*\" %1, %2",
             "%4 = binop \"+\" %0, %3", "%5 = apply @print(%4)"], SIL)
    arrow(ax, (5.5, 2.4), (7.4, 2.4))
    ax.text(6.45, 2.75, "-O", ha="center", fontsize=10, fontweight="bold", color="#b5651d")
    codebox(ax, 9.6, 2.4, "optimized SIL",
            ["", "%4 = integer_literal 7", "%5 = apply @print(%4)", "",
             "(constants folded;", " dead instrs removed)"], HL)

    ax.set_title("Concept 15 — the optimizer's spine: a pass manager running SIL→SIL transforms",
                 fontsize=12.5, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "pipeline.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_pipeline()
