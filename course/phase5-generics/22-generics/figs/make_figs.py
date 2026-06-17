#!/usr/bin/env python3
"""Figures for 22-generics/explainer.qmd.

    .venv/bin/python phase5-generics/22-generics/figs/make_figs.py

Produces:
    figs/erasure.png — the unspecialized generic lowering: ONE compiled copy of the function
    body (T erased to its constraint's existential); each call site wraps its concrete
    arguments and opens the T-result back to the statically-known type.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
SRC = "#eef2f7"
ERA = "#fff3d6"
CALL = "#dceede"


def box(ax, x, y, w, h, lines, color, title=None):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.08",
                 linewidth=1.4, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.38
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=9.5, fontweight="bold", color=TEXT, zorder=4)
        ty -= 0.44
    for ln in lines:
        ax.text(x + w / 2, ty, ln, ha="center", fontsize=8.4, family="monospace", color=TEXT, zorder=4)
        ty -= 0.38


def arr(ax, p0, p1, label=None, dx=0, dy=0, color="#b5651d"):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=13, linewidth=1.7,
                 color=color, zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center",
                fontsize=8.4, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(11.8, 6.0))
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 7)
    ax.axis("off")

    box(ax, 0.3, 4.3, 4.0, 2.2, ["func pick<T: P>(a: T, b: T) -> T {", "  if a.v() > b.v() { return a }", "  return b", "}"],
        SRC, title="source: a GENERIC function")
    box(ax, 4.6, 0.6, 4.0, 2.4, ["sil @pick(a: any P, b: any P)", "           -> any P {", "  witness_method %a, #0 …", "}"],
        ERA, title="compiled ONCE — T erased")
    arr(ax, (2.5, 4.2), (5.6, 3.1), label="erase T -> any P\n(its constraint)", dx=-1.5, dy=0.3)

    box(ax, 8.9, 4.3, 3.9, 2.2, ["pick(A(x:3), A(x:8))", "  wrap: init_existential ×2", "  call @pick", "  open_existential -> A"],
        CALL, title="call site (T inferred = A)")
    arr(ax, (9.6, 4.2), (8.0, 3.1), label="wrap args /\nopen result", dx=1.3, dy=0.35)

    ax.text(6.5, 0.15, "ONE body serves every conformer; the call boundary does the (un)wrapping.  Concept 24 clones it per type instead — specialization.",
            ha="center", fontsize=9.5, color="#444", style="italic")
    ax.text(6.5, 6.7, "Unspecialized generics = erasure to the constraint's existential — static T, dynamic dispatch inside",
            ha="center", fontsize=12, fontweight="bold", color=TEXT)
    fig.tight_layout()
    out = os.path.join(HERE, "erasure.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
