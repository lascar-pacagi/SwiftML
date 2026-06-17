#!/usr/bin/env python3
"""Figures for 03-sema/explainer.qmd.

    .venv/bin/python phase1-minimal/03-sema/figs/make_figs.py

Produces:
    figs/env_walk.png — sema as a single walk threading an ENVIRONMENT: each statement is
    checked against the env-so-far, then extends it. The two classic rejections fall out of
    the threading order: the initializer is checked BEFORE its own name is added (so
    `let x = x` fails), and assignment consults mutability (so `c = 9` on a `let` fails).
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"
TEXT = "#1b2733"
OK = "#dceede"
ERR = "#f3d6d6"
ENV = "#eef2f7"


def code(ax, x, y, txt, color, w=3.6, h=0.62, err=False):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.03,rounding_size=0.05",
                 linewidth=(1.8 if err else 1.2), edgecolor=("#b22" if err else EDGE), facecolor=color, zorder=3))
    ax.text(x, y, txt, ha="center", va="center", fontsize=9.5, family="monospace", color=TEXT, zorder=4)


def env(ax, x, y, txt):
    code(ax, x, y, txt, ENV, w=4.6, h=0.62)


def arrow(ax, p0, p1, color=EDGE):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=11, linewidth=1.3, color=color, zorder=2))


def make():
    fig, ax = plt.subplots(figsize=(10.6, 6.2))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 8.4)
    ax.axis("off")

    ax.text(2.6, 8.0, "program (checked in order)", fontsize=11, fontweight="bold", color=TEXT, ha="center")
    ax.text(8.8, 8.0, "environment threaded through the walk", fontsize=11, fontweight="bold", color=TEXT, ha="center")

    rows = [
        ("let a = 1", OK, False, "{ }            checks 1 — then adds a",        "{ a:let }"),
        ("var b = a + 2", OK, False, "{ a:let }      a in scope — then adds b",   "{ a:let, b:var }"),
        ("let x = x", ERR, True, "init checked BEFORE x is added:\n\"cannot find 'x' in scope\"", "{ a:let, b:var }"),
        ("b = 7", OK, False, "b is var — assignment OK",                          "{ a:let, b:var }"),
        ("a = 9", ERR, True, "a is let:\n\"cannot assign to value: 'a' is a 'let' constant\"", "{ a:let, b:var }"),
    ]
    y = 7.0
    for stmt, col, is_err, note, env_after in rows:
        code(ax, 2.6, y, stmt, col, err=is_err)
        arrow(ax, (4.5, y), (6.4, y), "#b22" if is_err else "#2f6f4f")
        env(ax, 8.8, y, env_after)
        ax.text(5.45, y + 0.42, note, fontsize=7.6, color=("#b22" if is_err else "#444"),
                ha="center", style="italic")
        y -= 1.45

    ax.text(6.0, 0.35, "one pass, one rule: check each statement against the env-so-far, THEN extend the env",
            fontsize=10.5, color=TEXT, ha="center", fontweight="bold")
    out = os.path.join(HERE, "env_walk.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
