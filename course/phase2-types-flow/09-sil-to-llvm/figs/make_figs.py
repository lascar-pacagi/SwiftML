#!/usr/bin/env python3
"""Figures for 09-sil-to-llvm/explainer.qmd.

    .venv/bin/python phase2-types-flow/09-sil-to-llvm/figs/make_figs.py

Produces:
    figs/pipeline.png — the complete Phase-2 pipeline, source to native, with the concept
    that builds each stage. IRGen (concept 09) is the last hop; then clang + the program runs.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
STAGE = "#fff3d6"
ART = "#eef2f7"
HL = "#dceede"


def stage(ax, x, y, label, sub, color, w=1.7, h=0.95):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.03,rounding_size=0.08",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ax.text(x, y + 0.13, label, ha="center", va="center", fontsize=10.5, fontweight="bold", color=TEXT, zorder=4)
    ax.text(x, y - 0.22, sub, ha="center", va="center", fontsize=7.5, color="#777", fontstyle="italic", zorder=4)


def artifact(ax, x, y, label):
    ax.text(x, y, label, ha="center", va="center", fontsize=8.5, family="monospace", color=TEXT, zorder=4)


def arr(ax, x0, x1, y):
    ax.add_patch(FancyArrowPatch((x0, y), (x1, y), arrowstyle="-|>", mutation_scale=12, linewidth=1.4, color=EDGE, zorder=2))


def make_pipeline():
    fig, ax = plt.subplots(figsize=(11.5, 3.4))
    ax.set_xlim(0, 23)
    ax.set_ylim(0, 4)
    ax.axis("off")
    y = 2.4
    # stages and the artifacts flowing between them
    stages = [
        ("Lexer", "01", STAGE), ("Parser", "02", STAGE), ("Sema", "03·05–07", STAGE),
        ("SILGen", "08", STAGE), ("IRGen", "09", HL), ("clang", "—", ART),
    ]
    arts = [".swift", "tokens", "AST", "typed AST", "SIL", "LLVM IR", "a.out"]
    xs_stage = [2.2, 5.6, 9.0, 12.4, 15.8, 19.2]
    xs_art = [0.6, 3.9, 7.3, 10.7, 14.1, 17.5, 21.4]
    for (lbl, sub, col), x in zip(stages, xs_stage):
        stage(ax, x, y, lbl, sub, col)
    for a, x in zip(arts, xs_art):
        artifact(ax, x, y + 1.05, a)
    # arrows: artifact -> stage -> artifact ...
    seq = []
    for i in range(len(xs_stage)):
        seq.append((xs_art[i] + 0.5, xs_stage[i] - 0.9))
        seq.append((xs_stage[i] + 0.9, xs_art[i + 1] - 0.5))
    for x0, x1 in seq:
        arr(ax, x0, x1, y)
    ax.text(21.4, y - 0.7, "./a.out\nruns!", ha="center", fontsize=9, color="#2f6f4f", fontweight="bold")
    ax.set_title("The complete Phase-2 pipeline — source to native (IRGen, concept 09, is the last hop)",
                 fontsize=12.5, color=TEXT, pad=6)
    fig.tight_layout()
    out = os.path.join(HERE, "pipeline.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_pipeline()
