#!/usr/bin/env python3
"""Figures for 26-arc-runtime/explainer.qmd.

    .venv/bin/python phase6-classes-arc/26-arc-runtime/figs/make_figs.py

Produces:
    figs/arc.png — the life of an object under ARC: the refcount events of
    `let a = T(1); let c = a` from birth (+1) through borrow (retain) to the scope-end
    releases and the deallocation sequence (deinit-body chain, field-destroy chain, free).
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
CODE = "#eef2f7"
RC = "#fff3d6"
DIE = "#f3d6d6"


def box(ax, x, y, w, h, lines, color, fs=8.8, title=None):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.07",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.36
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=9.4, fontweight="bold", color=TEXT, zorder=4)
        ty -= 0.42
    for ln in lines:
        ax.text(x + w / 2, ty, ln, ha="center", fontsize=fs, family="monospace", color=TEXT, zorder=4)
        ty -= 0.38


def make():
    fig, ax = plt.subplots(figsize=(11.8, 6.2))
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 7)
    ax.axis("off")

    rows = [
        ("let a = T(1)", "alloc_ref (+1), init runs;\nthe fresh +1 is CONSUMED by a's slot", "rc = 1"),
        ("let c = a", "a BORROWED load — c's slot\nmust own it too: RETAIN", "rc = 2"),
        ("print(c.id)", "borrowed use: no traffic", "rc = 2"),
        ("} // scope ends", "release c (newest first)\nrelease a", "rc = 1 -> 0"),
    ]
    y = 5.7
    for code, action, rc in rows:
        box(ax, 0.4, y, 3.3, 0.95, [code], CODE)
        box(ax, 4.2, y, 4.7, 0.95, action.split("\n"), CODE, fs=8.2)
        box(ax, 9.4, y, 1.7, 0.95, [rc], RC)
        y -= 1.18

    box(ax, 1.2, 0.25, 10.4, 1.15,
        ["rc hits 0  ->  vtable[0]: deinit BODIES (derived -> base)  ->  vtable[1]: FIELD releases (base -> derived)  ->  free"],
        DIE, fs=8.6, title="deallocation (the runtime's release — order verified against swiftc)")
    ax.text(6.5, 6.85, "ARC: every owner holds +1 — fresh values transfer, borrowed values retain, scope exits release",
            ha="center", fontsize=11.6, fontweight="bold", color=TEXT)
    fig.tight_layout()
    out = os.path.join(HERE, "arc.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
