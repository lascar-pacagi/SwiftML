#!/usr/bin/env python3
"""Figures for 13-optionals/explainer.qmd.

    .venv/bin/python phase3-value-types/13-optionals/figs/make_figs.py

Produces:
    figs/optional_enum.png — Optional<T> is just `enum { none; some(T) }`. Two values shown
    as { tag, payload }, and the table of how each piece of optional sugar desugars to a tag op.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, FancyBboxPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
TAG = "#ffe0c2"
PAY = "#dceede"
DEAD = "#eef2f7"
HL = "#fff3d6"


def value(ax, x, y, title, tag, payload, live):
    ax.text(x, y + 0.75, title, ha="center", fontsize=11, family="monospace", fontweight="bold", color=TEXT)
    cw = 1.5
    ax.add_patch(Rectangle((x - cw, y - 0.4), cw, 0.8, facecolor=TAG, edgecolor=EDGE, lw=1.2))
    ax.text(x - cw / 2, y, f"tag={tag}", ha="center", va="center", fontsize=10, family="monospace", color=TEXT)
    ax.add_patch(Rectangle((x, y - 0.4), cw, 0.8, facecolor=(PAY if live else DEAD), edgecolor=EDGE, lw=1.2))
    ax.text(x + cw / 2, y, payload, ha="center", va="center", fontsize=10, family="monospace",
            color=(TEXT if live else "#aaa"))


def make_optional_enum():
    fig, ax = plt.subplots(figsize=(11.0, 6.0))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 8)
    ax.axis("off")

    ax.text(6, 7.4, "Optional<T> is just an enum:   enum { case none;  case some(T) }",
            ha="center", fontsize=13, family="monospace", color=TEXT, fontweight="bold")

    value(ax, 3.0, 5.7, "nil  =  .none", 0, "–", False)
    value(ax, 9.0, 5.7, "Int?(5)  =  .some(5)", 1, "5", True)

    # sugar -> desugaring table
    rows = [
        ("nil", "→  .none   (tag 0)"),
        ("5      (where T? is expected)", "→  .some(5)   (implicit wrap, tag 1)"),
        ("x!", "→  tag == 1 ?  payload  :  TRAP"),
        ("if let v = x { … }", "→  if tag == 1 { v = payload; … }"),
        ("x ?? d", "→  tag == 1 ?  payload  :  d"),
        ("x == nil", "→  tag == 0"),
    ]
    y = 3.5
    ax.add_patch(FancyBboxPatch((0.8, 0.3), 10.4, 4.1, boxstyle="round,pad=0.05,rounding_size=0.1",
                 linewidth=1.2, edgecolor=EDGE, facecolor="white", zorder=1))
    ax.text(2.0, 4.05, "sugar", ha="left", fontsize=10.5, fontweight="bold", color="#777")
    ax.text(6.5, 4.05, "desugars to (a tag op on the enum)", ha="left", fontsize=10.5, fontweight="bold", color="#777")
    for sugar, desugar in rows:
        ax.text(2.0, y, sugar, ha="left", va="center", fontsize=10, family="monospace", color=TEXT)
        ax.text(6.5, y, desugar, ha="left", va="center", fontsize=10, family="monospace", color="#b5651d")
        y -= 0.52

    ax.set_title("Optionals are sugar over the enum + pattern-matching engine you already built",
                 fontsize=12.5, color=TEXT, pad=8)
    fig.tight_layout()
    out = os.path.join(HERE, "optional_enum.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_optional_enum()
