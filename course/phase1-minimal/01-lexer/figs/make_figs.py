#!/usr/bin/env python3
"""Generate the figures embedded in 01-lexer/explainer.qmd.

Run from this concept dir (the Makefile/`make figs` may wrap this later):

    ../../.venv/bin/python figs/make_figs.py     # or any python with matplotlib

Produces:
    figs/dfa.png   — the lexer DFA: skip trivia, then dispatch on the first char.

Real figure, from a real script (per CLAUDE.md: diagrams come from figs/, not stock art).
"""
import math
import os
import matplotlib

matplotlib.use("Agg")  # headless: write a PNG, never open a window
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
from matplotlib.path import Path

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


def elbow(ax, pts, head=False, radius=0.22):
    """A right-angled connector drawn as a SINGLE path, with its corners rounded.

    Two butt-ended segments meeting at a corner leave a notch, and a hard 90° reads
    oddly beside boxes that are all rounded. Round each corner with a quadratic
    through the vertex, clamped so it never eats more than half of either leg.
    """
    verts = [pts[0]]
    codes = [Path.MOVETO]
    for i in range(1, len(pts) - 1):
        (px, py), (vx, vy), (nx, ny) = pts[i - 1], pts[i], pts[i + 1]
        din = math.hypot(vx - px, vy - py)
        dout = math.hypot(nx - vx, ny - vy)
        r = min(radius, din / 2, dout / 2)
        a = (vx + (px - vx) / din * r, vy + (py - vy) / din * r)
        b = (vx + (nx - vx) / dout * r, vy + (ny - vy) / dout * r)
        verts += [a, (vx, vy), b]
        codes += [Path.LINETO, Path.CURVE3, Path.CURVE3]
    verts.append(pts[-1])
    codes.append(Path.LINETO)
    ax.add_patch(
        FancyArrowPatch(
            path=Path(verts, codes),
            arrowstyle="-|>" if head else "-",
            mutation_scale=14,
            linewidth=1.3,
            color=EDGE,
            joinstyle="round",
            capstyle="round",
            zorder=1,
        )
    )


def line(ax, p0, p1):
    """A plain connector segment (no arrowhead)."""
    ax.add_patch(
        FancyArrowPatch(
            p0, p1, arrowstyle="-", linewidth=1.3, color=EDGE, zorder=1
        )
    )


# ---- memory layout: list-of-records vs struct-of-arrays --------------------
CELL = "#f3e2d0"  # list cons cells
REC = "#e8eef7"  # records
ARR = "#dceede"  # the soup's arrays
MISS = "#f6c9c2"  # a cache line that had to be fetched


def word(ax, x, y, w, label, color, fontsize=7.5):
    ax.add_patch(
        FancyBboxPatch(
            (x, y),
            w,
            0.42,
            boxstyle="round,pad=0.01,rounding_size=0.03",
            linewidth=0.9,
            edgecolor=EDGE,
            facecolor=color,
        )
    )
    ax.text(x + w / 2, y + 0.21, label, ha="center", va="center",
            fontsize=fontsize, color=TEXT)


def make_memory():
    # Stacked, not side by side: the page constrains width, so a portrait figure
    # renders each block larger than a landscape one of the same content.
    fig, ax = plt.subplots(figsize=(9.2, 9.8))
    ax.set_xlim(0, 11.0)
    ax.set_ylim(0, 11.8)
    ax.axis("off")

    # ---- top: the list ----------------------------------------------------
    ax.text(5.5, 11.35, "v0:  Token.t list", ha="center", fontsize=13,
            fontweight="bold", color=TEXT)
    ax.text(5.5, 10.95, "18.1 words/token  ·  5 blocks  ·  chased", ha="center",
            fontsize=10, color=TEXT, fontstyle="italic")

    blocks = [
        (1.1, 10.05, 3.2, "::  [ hdr | * | * ]", CELL),
        (5.6, 9.00, 3.6, "Token.t  [ hdr | kind | * ]", REC),
        (2.4, 7.95, 3.1, "span  [ hdr | * | * ]", REC),
        (0.7, 6.75, 3.6, "pos lo  [ hdr | line | col | off ]", REC),
        (5.6, 6.75, 3.6, "pos hi  [ hdr | line | col | off ]", REC),
        (2.6, 5.60, 3.8, "::  [ hdr | * | * ]   next token", CELL),
    ]
    for x, y, w, label, color in blocks:
        word(ax, x, y, w, label, color, fontsize=8.5)

    def hop(a, b):
        ax.add_patch(FancyArrowPatch(a, b, arrowstyle="-|>", mutation_scale=10,
                                     linewidth=1.1, color=EDGE, zorder=1))

    hop((2.70, 10.05), (7.40, 9.42))     # cons    -> Token.t
    hop((7.40, 9.00), (3.95, 8.37))      # Token.t -> span
    hop((3.30, 7.95), (2.50, 7.17))      # span    -> pos lo
    hop((4.20, 7.95), (7.40, 7.17))      # span    -> pos hi
    elbow(ax, [(1.1, 10.26), (0.28, 10.26), (0.28, 5.81), (2.6, 5.81)], head=True)

    ax.text(5.5, 4.95,
            "five blocks, five addresses.  Each arrow is a load that must finish before\n"
            "the next address is even known — a prefetcher cannot run ahead of a chase.",
            ha="center", va="center", fontsize=9, color=TEXT, fontstyle="italic")

    # ---- bottom: the soup -------------------------------------------------
    ax.text(5.5, 4.25, "v1:  the token soup", ha="center", fontsize=13,
            fontweight="bold", color=TEXT)
    ax.text(5.5, 3.85, "4.0 words/token  ·  3 arrays  ·  walked", ha="center",
            fontsize=10, color=TEXT, fontstyle="italic")

    cw, x0 = 0.62, 2.35
    for name, y in zip(["tags", "starts", "ends"], [2.85, 2.10, 1.35]):
        ax.text(x0 - 0.18, y + 0.21, name, ha="right", va="center", fontsize=10,
                color=TEXT)
        for k in range(12):
            word(ax, x0 + k * cw, y, cw - 0.03, str(k), ARR, fontsize=7.5)

    ax.add_patch(
        FancyBboxPatch((x0 - 0.04, 2.77), 8 * cw - 0.02, 0.58,
                       boxstyle="round,pad=0.02,rounding_size=0.04",
                       linewidth=1.9, edgecolor="#b4453a", facecolor="none", zorder=4))
    ax.text(x0 + 4 * cw, 3.47, "one 64-byte cache line = 8 tags",
            ha="center", fontsize=9.5, color="#b4453a", fontweight="bold")

    ax.text(5.5, 0.92,
            "column i IS token i.  Reading every tag is a stride-1 walk: one cache line\n"
            "serves eight tokens, and the prefetcher sees it coming.",
            ha="center", va="center", fontsize=9, color=TEXT, fontstyle="italic")

    ax.add_patch(FancyBboxPatch((0.5, 0.12), 10.0, 0.56,
                                boxstyle="round,pad=0.02,rounding_size=0.05",
                                linewidth=1.1, edgecolor=EDGE, facecolor="#f7f7f4"))
    ax.text(5.5, 0.40,
            "cache lines touched to read one token's kind:    "
            "v0  two or more, unrelated    ·    v1  one eighth",
            ha="center", va="center", fontsize=10, color=TEXT)

    fig.tight_layout()
    out = os.path.join(HERE, "memory.png")
    fig.savefig(out, dpi=170)
    print("wrote", out)


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

    # dispatch fan-out: four branches down to scan steps, then to emitted tokens.
    # Routed as an elbow (stub -> shared rail -> one vertical drop per branch) rather
    # than as diagonals: a guard label beside a vertical drop has the whole column to
    # itself, where on a shallow diagonal fan it lands on top of a neighbouring edge.
    branches = [
        # x,   scan label,                       token label
        (1.4, "scan digits\n(maximal munch)", "Int(n)"),
        (3.8, "scan ident\n→ keyword table", "Ident / let / var"),
        (6.2, "single char", "+ - * / % = ( ) ,"),
        (8.6, "—", "Newline"),
    ]
    guards = ["0–9", "A–Z a–z _", "operator / punct", "\\n"]
    rail = 3.62
    line(ax, (5, 3.90), (5, rail))  # the stub, drawn once: four rounded corners
    for (x, scan, tok), guard in zip(branches, guards):  # here would arch over the rail
        elbow(ax, [(5, rail), (x, rail), (x, 3.02)], head=True)
        ax.text(
            x + 0.14,
            3.30,
            guard,
            ha="left",
            va="center",
            fontsize=8.5,
            color=TEXT,
            fontstyle="italic",
            zorder=6,
        )
        box(ax, x, 2.52, 2.05, 0.95, scan, TRIVIA, fontsize=9)
        arrow(ax, (x, 2.04), (x, 1.58))
        box(ax, x, 1.15, 2.05, 0.7, tok, EMIT, fontsize=9, bold=True)

    # loop-back: emitted token -> next() (driver calls next again), routed up the
    # right margin as a clean elbow so it never crosses the dispatch fan.
    rx = 10.8
    # out of the Newline terminal, up the margin, back into next()
    elbow(ax, [(9.63, 1.15), (rx, 1.15), (rx, 8.4), (6.12, 8.4)], head=True)
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
    make_memory()
