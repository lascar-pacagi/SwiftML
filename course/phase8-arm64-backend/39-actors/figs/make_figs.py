#!/usr/bin/env python3
"""figs/actors.png — actor isolation. An actor's state is reachable from outside ONLY through await
(a hop onto its executor, which serializes access); a synchronous call is a compile error. Inside
the actor, self-access is direct. The guarantee is enforced at COMPILE time."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.4):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.03,rounding_size=0.05",
                 linewidth=1.3, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.30
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=9.0, fontweight="bold", color=TEXT, zorder=4); ty -= 0.40
    for ln in lines:
        col = "#c0392b" if ln.startswith("X ") else ("#2a7" if ln.startswith("OK") else TEXT)
        ax.text(x + 0.18, ty, ln.lstrip("X ").replace("OK ", ""), ha="left", fontsize=fs, family="monospace", color=col, zorder=4); ty -= 0.33


def arr(ax, p0, p1, color, label=None, dy=0.13):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=12, linewidth=1.8, color=color, zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2 + dy, label, ha="center", fontsize=8.2, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(12.6, 5.8)); ax.set_xlim(0, 13); ax.set_ylim(0, 6.2); ax.axis("off")
    ax.text(6.5, 5.9, "Actor isolation: an actor's state is reachable from outside only through `await`",
            ha="center", fontsize=11.6, fontweight="bold", color=TEXT)

    # the actor
    box(ax, 4.6, 2.2, 3.8, 3.0,
        ["actor Bank {", "  var balance   <- isolated", "  func deposit(n) {", "    balance += n   OK direct", "  }", "}"],
        "#e8f6ee", title="the actor (serialized)", fs=8.2)

    # outside callers
    box(ax, 0.3, 3.4, 3.6, 1.7,
        ["await b.deposit(50)", "OK  -> hop onto the", "      actor's executor"],
        "#dceede", title="caller (awaited)", fs=8.2)
    box(ax, 0.3, 1.2, 3.6, 1.7,
        ["b.deposit(50)", "X  COMPILE ERROR:", "X  actor-isolated, sync"],
        "#fdeded", title="caller (synchronous)", fs=8.2)

    arr(ax, (3.9, 4.25), (4.6, 4.0), "#2a8", label="await = hop", dy=0.16)
    arr(ax, (3.9, 2.05), (4.6, 2.9), "#c0392b", label="rejected", dy=-0.18)

    box(ax, 8.7, 2.2, 4.0, 3.0,
        ["the rule (sema, compile time):", "",
         "reject  a.method()  when", "  a is an actor, AND", "  not under `await`, AND",
         "  not inside the actor.", "", "runtime = the class machinery."],
        "#fff8e1", title="enforced at COMPILE time", fs=8.0)

    box(ax, 1.2, 0.3, 10.6, 0.75,
        ["Inside the actor: self-access is synchronous. Outside: `await` only. A regular `class` has no isolation.",
         "Our executor is serial, so runtime serialization is automatic -- the value of actors is the compile-time guarantee."],
        "#eef2f7", fs=7.8)

    fig.tight_layout()
    out = os.path.join(HERE, "actors.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
