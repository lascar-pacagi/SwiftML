#!/usr/bin/env python3
"""Figures for 25-classes-vtables/explainer.qmd.

    .venv/bin/python phase6-classes-arc/25-classes-vtables/figs/make_figs.py

Produces:
    figs/vtable.png — two objects, two vtables, one call site: the heap object's first word
    points at its class's vtable; `a.sound()` loads slot #0 from whatever table the OBJECT
    carries — the override wins because slot NUMBERING is inherited.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
OBJ = "#fff3d6"
VT = "#dceede"
FN = "#eef2f7"


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


def arr(ax, p0, p1, label=None, dx=0, dy=0, rad=0.0, color="#b5651d"):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.6,
                 color=color, zorder=5, connectionstyle=f"arc3,rad={rad}"))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center",
                fontsize=8.2, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(11.8, 6.4))
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 7.2)
    ax.axis("off")

    box(ax, 0.4, 5.3, 3.4, 1.6, ["let a: Animal = Dog(4)", "a.sound()   // slot #0", "a.describe()// slot #1"], FN,
        title="call site (static: Animal)")

    box(ax, 5.0, 4.6, 3.0, 2.2, ["vtable ptr ──►", "refcount: 1", "legs = 4"], OBJ, title="the Dog object (heap)")
    box(ax, 9.4, 4.4, 3.2, 2.4, ["#0: Dog.sound", "#1: Animal.describe", "#2: Dog.fetch"], VT, title="@vtbl.Dog")
    box(ax, 9.4, 0.7, 3.2, 2.0, ["#0: Animal.sound", "#1: Animal.describe"], VT, title="@vtbl.Animal")
    box(ax, 5.0, 0.9, 3.0, 1.8, ["vtable ptr ──►", "refcount: 1", "legs = 2"], OBJ, title="an Animal object")

    arr(ax, (3.85, 5.9), (4.95, 5.8), label="load word 0,\nindex SLOT", dx=0.15, dy=0.65)
    arr(ax, (8.05, 5.9), (9.35, 5.7))
    arr(ax, (8.05, 2.0), (9.35, 1.8))
    ax.text(6.5, 7.0, "Same call site, same slot number — the OBJECT chooses the table, the override wins",
            ha="center", fontsize=12, fontweight="bold", color=TEXT)
    ax.text(2.0, 2.2, "Slot numbering is INHERITED:\nDog's #0/#1 mean what Animal's\n#0/#1 mean — an upcast changes\nnothing about dispatch.\n(An override replaces its slot's\nfunction pointer; new methods\nappend new slots.)",
            ha="center", fontsize=8.6, color="#444", style="italic")
    fig.tight_layout()
    out = os.path.join(HERE, "vtable.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
