#!/usr/bin/env python3
"""Generate the Phase-2 source-to-native pipeline for concept 09."""
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

HERE = Path(__file__).resolve().parent
INK = "#203247"
MUTED = "#627185"
LINE = "#9aa9b9"
TEAL = "#087f82"


def make_pipeline():
    fig, ax = plt.subplots(figsize=(12, 3.1))
    fig.patch.set_facecolor("white")
    ax.set(xlim=(-0.8, 12.8), ylim=(-1.05, 2.25))
    ax.axis("off")

    ax.text(-0.65, 1.98, "From Swift source to a running program",
            fontsize=17, weight="bold", color=INK, va="center")
    ax.text(-0.65, 1.58, "PHASE 2   /   CONCEPT 09",
            fontsize=9, weight="bold", color=MUTED, va="center")

    # Artifacts sit on the path; each labelled arrow is a compiler stage.
    artifacts = ["Swift\nsource", "Tokens", "AST", "Typed\nAST", "SIL", "LLVM IR", "Native\nexecutable"]
    stages = [("Lexer", "01"), ("Parser", "02"), ("Sema", "03 · 05–07"),
              ("SILGen", "08"), ("IRGen", "09 · you build"),
              ("clang", "compile + link")]
    y, width, height = 0.45, 1.3, 0.88
    for i, label in enumerate(artifacts):
        x = 2 * i
        highlighted = i in (4, 5)
        ax.add_patch(FancyBboxPatch(
            (x - width / 2, y - height / 2), width, height,
            boxstyle="round,pad=0.02,rounding_size=0.09",
            linewidth=1.3 if highlighted else 0.8,
            edgecolor=TEAL if highlighted else "#d8e0e8",
            facecolor="#edf8f7" if highlighted else "#f3f6f9"))
        ax.text(x, y, label, ha="center", va="center", fontsize=11,
                color=INK, weight="bold")

    for i, (name, concept) in enumerate(stages):
        x = 2 * i + 1
        color = TEAL if name == "IRGen" else MUTED
        ax.add_patch(FancyArrowPatch(
            (2 * i + width / 2 + 0.06, y),
            (2 * (i + 1) - width / 2 - 0.06, y),
            arrowstyle="-|>", mutation_scale=12, linewidth=1.5, color=color))
        ax.text(x, 1.12, name, ha="center", fontsize=10,
                weight="bold", color=color)
        ax.text(x, -0.23, concept, ha="center", fontsize=8, color=color)

    ax.plot([7.4, 10.6], [-0.53, -0.53], color=TEAL, linewidth=2,
            solid_capstyle="round")
    ax.text(9, -0.83, "This lesson: SIL → LLVM IR", ha="center",
            fontsize=10, weight="bold", color=TEAL)
    ax.text(12, -0.83, "Run ./a.out", ha="center", fontsize=10, color=INK)

    fig.subplots_adjust(left=0.025, right=0.975, top=0.97, bottom=0.06)
    out = HERE / "pipeline.png"
    fig.savefig(out, dpi=220, facecolor="white")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_pipeline()
