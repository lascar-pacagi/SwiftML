#!/usr/bin/env python3
"""Figures for 21-protocols-witness/explainer.qmd.

    .venv/bin/python phase5-generics/21-protocols-witness/figs/make_figs.py

Produces:
    figs/witness.png — dynamic dispatch through a witness table: the existential carries
    (payload, table ptr); the call site indexes the table by requirement SLOT, loads a
    function pointer (a thunk), and the thunk reloads the concrete self and calls the method.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
EX = "#fff3d6"
TBL = "#dceede"
FN = "#eef2f7"


def box(ax, x, y, w, h, lines, color, title=None, mono=True):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.08",
                 linewidth=1.4, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.38
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=9.5, fontweight="bold", color=TEXT, zorder=4)
        ty -= 0.42
    for ln in lines:
        ax.text(x + w / 2, ty, ln, ha="center", fontsize=8.6,
                family=("monospace" if mono else "sans-serif"), color=TEXT, zorder=4)
        ty -= 0.4


def arr(ax, p0, p1, label=None, dx=0, dy=0, rad=0.0, color="#b5651d"):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=13, linewidth=1.7,
                 color=color, zorder=5, connectionstyle=f"arc3,rad={rad}"))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center",
                fontsize=8.6, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(11.6, 6.0))
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 7)
    ax.axis("off")

    # call site
    box(ax, 0.3, 4.6, 3.6, 1.7, ["let s: Shape = c", "print(s.area())"], FN, title="call site (static type: any Shape)")
    # existential
    box(ax, 0.6, 1.4, 3.4, 2.2, ["payload: [N x i64]", "(the Circle{r=2})", "table ptr  ─────►"], EX, title="the existential s")
    arr(ax, (2.1, 4.5), (2.2, 3.7), label="wrap:\ninit_existential", dx=-1.35, dy=0.1)

    # witness table
    box(ax, 5.4, 1.2, 3.2, 2.6, ["#0: area    ►", "#1: scaled  ►", "", "(one per (type,proto))"], TBL,
        title="@wt.Shape.Circle")
    arr(ax, (4.05, 2.2), (5.35, 2.6), label="slot #0\n(requirement\norder)", dx=0.0, dy=1.1)

    # thunk + method
    box(ax, 9.3, 3.9, 3.4, 2.3, ["w.Shape.Circle.0(ptr self):", "  %c = load Circle, self", "  call @Circle.area(%c)"], FN,
        title="the THUNK (ABI adapter)")
    box(ax, 9.3, 0.7, 3.4, 1.9, ["Circle.area(self: Circle):", "  return 3 * r * r"], FN, title="the method")
    arr(ax, (8.65, 3.3), (9.5, 4.0), label="load fn ptr,\ncall(payload ptr)", dx=-0.7, dy=-0.65)
    arr(ax, (11.0, 3.85), (11.0, 2.7), label="direct call,\nconcrete self", dx=1.25, dy=0.0)

    ax.text(6.5, 6.6, "Dynamic dispatch through a witness table — the callee is chosen by the VALUE's table, not the static type",
            ha="center", fontsize=12, fontweight="bold", color=TEXT)
    fig.tight_layout()
    out = os.path.join(HERE, "witness.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
