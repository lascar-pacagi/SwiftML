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
    # The env is not a column of snapshots beside the code — it is ONE value handed from
    # each statement to the next. Draw that literally: env, statement, env, statement,
    # zig-zagging down, so "threaded through the walk" is something you can follow.
    fig, ax = plt.subplots(figsize=(9.6, 9.4))
    ax.set_xlim(0, 12)
    ax.set_ylim(1.5, 12.2)
    ax.axis("off")

    ax.text(6.0, 11.75, "one walk, one environment, handed along",
            fontsize=12.5, fontweight="bold", color=TEXT, ha="center")
    ax.text(6.0, 11.32,
            "each statement is checked against the environment it is given, then extends it",
            fontsize=9.5, color=TEXT, ha="center", style="italic")

    STMT_X, ENV_X = 3.0, 8.9
    rows = [
        # statement, error?, what the check consults, what it does to the env, env after
        ("let a = 1", False, "checks 1", "adds a", "{ a:let }"),
        ("var b = a + 2", False, "a is in scope", "adds b", "{ a:let, b:var }"),
        ("let x = x", True, "x is NOT in scope yet", "nothing added",
         "{ a:let, b:var }"),
        ("b = 7", False, "b is a var", "no new name", "{ a:let, b:var }"),
        ("a = 9", True, "a is a let", "nothing added", "{ a:let, b:var }"),
    ]

    y = 10.5
    env(ax, ENV_X, y, "{ }")
    ax.text(ENV_X, y + 0.52, "the empty env", fontsize=8.5, color="#666",
            ha="center", va="bottom", style="italic")

    for stmt, is_err, consults, effect, after in rows:
        ys, ye = y - 0.72, y - 1.44
        red = "#b22"
        # env  ->  statement : what it is checked against
        arrow(ax, (ENV_X - 2.35, y - 0.30), (STMT_X + 1.85, ys + 0.30))
        ax.text(6.45, (y + ys) / 2 + 0.16, consults, fontsize=8.2, color="#444",
                ha="right", va="center", style="italic")
        code(ax, STMT_X, ys, stmt, ERR if is_err else OK, err=is_err)
        # statement -> env : what it does to it
        arrow(ax, (STMT_X + 1.85, ys - 0.30), (ENV_X - 2.35, ye + 0.30),
              red if is_err else "#2f6f4f")
        ax.text(5.20, (ys + ye) / 2 - 0.16, effect, fontsize=8.2,
                color=red if is_err else "#2f6f4f", ha="right", va="center",
                style="italic")
        env(ax, ENV_X, ye, after)
        if is_err:
            ax.text(STMT_X - 1.85, ys - 0.40, "reported, walk continues", fontsize=8,
                    color=red, ha="left", va="top", style="italic")
        y = ye

    ax.text(6.0, 2.25,
            "The two rejections are the same rule read twice: `let x = x` fails because the\n"
            "initialiser is checked against the env BEFORE x joins it, and `a = 9` fails because\n"
            "the env remembers that a was bound by `let`.",
            fontsize=9.5, color=TEXT, ha="center", va="center")

    out = os.path.join(HERE, "env_walk.png")
    fig.savefig(out, dpi=170, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
