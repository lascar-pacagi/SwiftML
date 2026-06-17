#!/usr/bin/env python3
"""Figures for 11-enums-adts/explainer.qmd.

    .venv/bin/python phase3-value-types/11-enums-adts/figs/make_figs.py

Produces:
    figs/tagged_union.png — an enum is a TAG (which case) + a PAYLOAD (sized to the widest
    case). Three values of one enum, all the same size, differing in tag and live payload.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
TAG = "#ffe0c2"
PAY = "#dceede"
DEAD = "#eef2f7"


def enum_value(ax, x, y, title, tag, cells):
    # cells: list of (text, live?) for the payload slots
    n = 1 + len(cells)
    cw = 1.15
    w = cw * n + 0.2
    ax.text(x, y + 0.95, title, ha="center", fontsize=10.5, family="monospace", color=TEXT, fontweight="bold")
    x0 = x - w / 2 + 0.1
    # tag cell
    ax.add_patch(Rectangle((x0, y - 0.4), cw, 0.8, facecolor=TAG, edgecolor=EDGE, linewidth=1.2))
    ax.text(x0 + cw / 2, y, f"tag={tag}", ha="center", va="center", fontsize=9.5, family="monospace", color=TEXT)
    for i, (txt, live) in enumerate(cells):
        cx = x0 + cw * (i + 1)
        ax.add_patch(Rectangle((cx, y - 0.4), cw, 0.8, facecolor=(PAY if live else DEAD), edgecolor=EDGE, linewidth=1.2))
        ax.text(cx + cw / 2, y, txt, ha="center", va="center", fontsize=9.5, family="monospace",
                color=(TEXT if live else "#aaa"))


def make_tagged_union():
    fig, ax = plt.subplots(figsize=(11.0, 4.8))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 5)
    ax.axis("off")

    ax.text(6, 4.5, "enum Shape { case circle(Int);  case rect(Int, Int);  case dot }",
            ha="center", fontsize=11.5, family="monospace", color=TEXT)

    enum_value(ax, 2.4, 2.6, "Shape.circle(5)", 0, [("5", True), ("—", False)])
    enum_value(ax, 6.0, 2.6, "Shape.rect(3, 4)", 1, [("3", True), ("4", True)])
    enum_value(ax, 9.6, 2.6, "Shape.dot", 2, [("—", False), ("—", False)])

    ax.text(6, 0.85, "Every value is the same size — tag + the widest case's payload.  The tag says which case;\n"
            "only that case's payload slots are live.  (A struct is a PRODUCT — all fields; an enum is a SUM — one case.)",
            ha="center", fontsize=9.5, color="#555")
    fig.suptitle("A tagged union: an enum value is a tag (which case) + a payload (sized to the widest case)",
                 fontsize=12.5, color=TEXT, y=0.98)
    fig.tight_layout(rect=[0, 0, 1, 0.94])
    out = os.path.join(HERE, "tagged_union.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_tagged_union()
