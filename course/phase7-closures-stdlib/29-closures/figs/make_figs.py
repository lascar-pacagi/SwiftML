#!/usr/bin/env python3
"""Figures for 29-closures/explainer.qmd.

    .venv/bin/python phase7-closures-stdlib/29-closures/figs/make_figs.py

Produces:
    figs/closure.png — the closure ABI: the literal lifts to a top-level function taking a
    context; creation copies the captures into a refcounted heap context; the VALUE is the
    thick pair {code, ctx}; a named function rides the same ABI via a thunk + null context.
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
CTX = "#fff3d6"
PAIR = "#dceede"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.4):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.07",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.36
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=9.3, fontweight="bold", color=TEXT, zorder=4)
        ty -= 0.42
    for ln in lines:
        ax.text(x + w / 2, ty, ln, ha="center", fontsize=fs, family="monospace", color=TEXT, zorder=4)
        ty -= 0.38


def arr(ax, p0, p1, label=None, dx=0, dy=0):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.6,
                 color="#b5651d", zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center",
                fontsize=8.2, color="#b5651d", fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(11.8, 6.2))
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 7)
    ax.axis("off")

    box(ax, 0.3, 4.4, 4.2, 2.2,
        ["func makeAdder(n: Int)", "      -> (Int) -> Int {", "  return { (x: Int) -> Int", "           in x + n }", "}"],
        SRC, title="source: the literal CAPTURES n")
    box(ax, 0.3, 0.6, 4.2, 2.4,
        ["sil @makeAdder$clo0(", "    ctx: ptr, x: Int) {", "  %n = capture_get ctx, #0", "  return x + %n", "}"],
        SRC, title="LIFTED: a plain top-level fn")
    arr(ax, (2.4, 4.3), (2.4, 3.2), label="lift", dx=-0.6)

    box(ax, 5.4, 3.7, 3.2, 2.2, ["vtable: noop dtor", "refcount: 1", "n = 7"], CTX,
        title="the CONTEXT (heap, refcounted)")
    box(ax, 9.6, 3.9, 3.1, 1.8, ["code ──► $clo0", "ctx  ──► context"], PAIR, title="the VALUE: thick pair")
    arr(ax, (4.6, 5.3), (5.5, 5.0), label="creation copies\nthe capture", dx=0.1, dy=0.65)
    arr(ax, (8.7, 4.8), (9.7, 4.8))

    box(ax, 9.6, 0.8, 3.1, 1.8, ["code ──► dbl$thunk", "ctx  ──► null"], PAIR,
        title="a NAMED fn as a value")
    ax.text(7.6, 1.7, "thin -> thick: a thunk ignores the\nctx; null makes its ARC traffic free",
            ha="center", fontsize=8.4, color="#444", style="italic")
    ax.text(6.5, 6.8, "The closure ABI: one calling convention — code(ctx, args) — for closures and named functions alike",
            ha="center", fontsize=11.4, fontweight="bold", color=TEXT)
    fig.tight_layout()
    out = os.path.join(HERE, "closure.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
