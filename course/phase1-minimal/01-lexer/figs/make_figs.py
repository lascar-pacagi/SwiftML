#!/usr/bin/env python3
"""Generate the figures embedded in 01-lexer/explainer.qmd.

Run from this concept dir (the Makefile/`make figs` may wrap this later):

    ../../.venv/bin/python figs/make_figs.py     # or any python with matplotlib

Produces:
    figs/dfa.png   — the lexer DFA: skip trivia, then dispatch on the first char.

Real figure, from a real script (per CLAUDE.md: diagrams come from figs/, not stock art).
"""
import os
import matplotlib

matplotlib.use("Agg")  # headless: write a PNG, never open a window
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))

# ---- palette ---------------------------------------------------------------
TRIVIA = "#e8eef7"  # skip/trivia steps
DECIDE = "#fff3d6"  # decision diamonds (drawn as rounded boxes for simplicity)
EMIT = "#dceede"  # emitted-token terminals
EDGE = "#5b6b7b"
TEXT = "#1b2733"


def box(ax, x, y, w, h, label, color, fontsize=10, bold=False):
    """A rounded node centered at (x, y)."""
    ax.add_patch(
        FancyBboxPatch(
            (x - w / 2, y - h / 2),
            w,
            h,
            boxstyle="round,pad=0.02,rounding_size=0.08",
            linewidth=1.2,
            edgecolor=EDGE,
            facecolor=color,
        )
    )
    ax.text(
        x,
        y,
        label,
        ha="center",
        va="center",
        fontsize=fontsize,
        color=TEXT,
        fontweight="bold" if bold else "normal",
        zorder=5,
    )


def arrow(ax, p0, p1, label=None, rad=0.0, lx=0.0, ly=0.0):
    ax.add_patch(
        FancyArrowPatch(
            p0,
            p1,
            connectionstyle=f"arc3,rad={rad}",
            arrowstyle="-|>",
            mutation_scale=14,
            linewidth=1.3,
            color=EDGE,
            zorder=1,
        )
    )
    if label:
        mx, my = (p0[0] + p1[0]) / 2 + lx, (p0[1] + p1[1]) / 2 + ly
        ax.text(
            mx,
            my,
            label,
            ha="center",
            va="center",
            fontsize=8.5,
            color=TEXT,
            fontstyle="italic",
            zorder=6,
        )


def line(ax, p0, p1):
    """A plain connector segment (no arrowhead)."""
    ax.add_patch(
        FancyArrowPatch(
            p0, p1, arrowstyle="-", linewidth=1.3, color=EDGE, zorder=1
        )
    )


def make_dfa():
    fig, ax = plt.subplots(figsize=(9.8, 6.4))
    ax.set_xlim(0, 11.4)
    ax.set_ylim(0, 9)
    ax.axis("off")

    # central spine (top -> down)
    box(ax, 5, 8.4, 2.2, 0.7, "next()", EMIT, bold=True)
    box(ax, 5, 7.1, 4.4, 0.95, "skip trivia\nspaces · tabs · //… · /*…*/ (nests)", TRIVIA)
    box(ax, 5, 5.7, 3.0, 0.8, "at end of input?", DECIDE)
    box(ax, 5, 4.3, 3.6, 0.8, "dispatch on first char", DECIDE, bold=True)

    arrow(ax, (5, 8.05), (5, 7.58))
    arrow(ax, (5, 6.62), (5, 6.10))
    arrow(ax, (5, 5.30), (5, 4.70), "no", lx=0.28)

    # EOF terminal (to the right of "at end?")
    box(ax, 8.7, 5.7, 1.7, 0.7, "Eof", EMIT, bold=True)
    arrow(ax, (6.5, 5.7), (7.85, 5.7), "yes", ly=0.26)

    # dispatch fan-out: four branches down to scan steps, then to emitted tokens
    branches = [
        # x,   scan label,                       token label
        (1.4, "scan digits\n(maximal munch)", "Int(n)"),
        (3.8, "scan ident\n→ keyword table", "Ident / let / var"),
        (6.2, "single char", "+ - * / % = ( ) ,"),
        (8.6, "—", "Newline"),
    ]
    guards = ["0–9", "A–Z a–z _", "operator/punct", "\\n"]
    for (x, scan, tok), guard in zip(branches, guards):
        # from dispatch box bottom to each scan node
        arrow(ax, (5, 3.90), (x, 3.18), guard, rad=0.0, lx=(x - 5) * 0.16, ly=0.18)
        box(ax, x, 2.7, 2.05, 0.95, scan, TRIVIA, fontsize=9)
        arrow(ax, (x, 2.22), (x, 1.62))
        box(ax, x, 1.15, 2.05, 0.7, tok, EMIT, fontsize=9, bold=True)

    # loop-back: emitted token -> next() (driver calls next again), routed up the
    # right margin as a clean elbow so it never crosses the dispatch fan.
    rx = 10.8
    line(ax, (9.63, 1.15), (rx, 1.15))  # right out of the Newline terminal
    line(ax, (rx, 1.15), (rx, 8.4))  # up the margin
    arrow(ax, (rx, 8.4), (6.12, 8.4))  # left into next()
    ax.text(
        rx + 0.12,
        4.8,
        "loop: the driver\ncalls next() again",
        ha="left",
        va="center",
        rotation=90,
        fontsize=8.5,
        color=TEXT,
        fontstyle="italic",
    )

    ax.set_title(
        "The lexer DFA — skip trivia, then dispatch on the first character",
        fontsize=12,
        color=TEXT,
        pad=10,
    )
    fig.tight_layout()
    out = os.path.join(HERE, "dfa.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make_dfa()
