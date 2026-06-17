#!/usr/bin/env python3
"""Figures for 27-ownership/explainer.qmd.

    .venv/bin/python phase6-classes-arc/27-ownership/figs/make_figs.py

Produces:
    figs/ownership.png — the ownership lattice of one function: guaranteed values (params,
    loads) flow without traffic; owned values (alloc/copy/take) each carry a +1 that must be
    consumed exactly once; the verifier's three rules annotate the violations.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
OWN = "#fff3d6"
GUA = "#dceede"
BAD = "#f3d6d6"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.6):
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
    fig, ax = plt.subplots(figsize=(11.6, 6.2))
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 7)
    ax.axis("off")

    box(ax, 0.4, 3.9, 3.9, 2.5,
        ["born owning +1:", "alloc_ref", "copy_value (of a borrow)", "load [take] (slot dies)", "class-typed call results"],
        OWN, title="OWNED — consume EXACTLY once")
    box(ax, 4.6, 3.9, 3.9, 2.5,
        ["+0, alive by someone", "else's ownership:", "parameters (incl. self)", "plain loads", "— never consumed, no traffic"],
        GUA, title="GUARANTEED — a borrow")
    box(ax, 8.8, 3.9, 3.9, 2.5,
        ["consumers take the +1:", "destroy_value", "store (into a slot/field)", "return"],
        OWN, title="CONSUMERS")

    box(ax, 0.4, 0.5, 12.3, 2.6,
        ["R1  owned consumed 0 times  ->  \"owned value %N is leaked\"          (deinit never fires)",
         "R1  owned consumed 2+ times ->  \"consumed N times\"                  (double-free)",
         "R2  guaranteed consumed     ->  \"consumed without a copy_value\"     (corrupts the caller's count)",
         "R3  owned used after its consuming use  ->  \"used after being consumed\"  (use-after-free)"],
        BAD, title="THE VERIFIER — ARC bugs become compile errors", fs=8.2)
    ax.text(6.5, 6.8, "Ownership SSA: every class value is OWNED (+1, consumed once) or GUARANTEED (a borrow, never consumed)",
            ha="center", fontsize=11.2, fontweight="bold", color=TEXT)
    fig.tight_layout()
    out = os.path.join(HERE, "ownership.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
