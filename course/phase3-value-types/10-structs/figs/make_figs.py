#!/usr/bin/env python3
"""Generate the value-semantics figure for concept 10."""
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Rectangle

HERE = Path(__file__).resolve().parent
INK = "#203247"
MUTED = "#627185"
LINE = "#9aa9b9"
TEAL = "#087f82"
GREEN = "#dff1e7"
ORANGE = "#c66719"
ORANGE_FILL = "#fff0df"
PANEL = "#f6f8fa"


def struct_slot(ax, x, y, variable, fields, changed_field=None):
    """Draw one stack slot containing a two-field Point value."""
    width, height = 1.85, 1.52
    ax.add_patch(FancyBboxPatch(
        (x - width / 2, y - height / 2), width, height,
        boxstyle="round,pad=0.02,rounding_size=0.08",
        linewidth=1.25, edgecolor=LINE, facecolor="white", zorder=2))
    ax.text(x, y + 0.51, f"{variable} : Point", ha="center", va="center",
            fontsize=12.5, weight="bold", color=INK, zorder=4)

    for index, (field_name, field_value) in enumerate(fields):
        field_y = y + 0.08 - index * 0.48
        is_changed = index == changed_field
        ax.add_patch(Rectangle(
            (x - 0.76, field_y - 0.19), 1.52, 0.38,
            facecolor=ORANGE_FILL if is_changed else GREEN,
            edgecolor=ORANGE if is_changed else "#8aaf9c",
            linewidth=1.15, zorder=3))
        ax.text(x - 0.57, field_y, field_name, ha="left", va="center",
                fontsize=11.5, family="monospace", color=MUTED, zorder=4)
        ax.text(x + 0.58, field_y, str(field_value), ha="right", va="center",
                fontsize=12, family="monospace", weight="bold", color=INK, zorder=4)


def panel(ax, x, title, source):
    ax.add_patch(FancyBboxPatch(
        (x, 0.2), 5.55, 3.15,
        boxstyle="round,pad=0.04,rounding_size=0.12",
        linewidth=0.9, edgecolor="#d8e0e8", facecolor=PANEL, zorder=0))
    ax.text(x + 0.3, 3.02, title, fontsize=13.5, weight="bold", color=INK)
    ax.text(x + 0.3, 2.65, source, fontsize=12, family="monospace", color=TEAL)


def make_value_semantics():
    fig, ax = plt.subplots(figsize=(12, 4.55))
    fig.patch.set_facecolor("white")
    ax.set(xlim=(0, 12), ylim=(0, 4.7))
    ax.axis("off")

    ax.text(0.2, 4.42, "Assignment copies a struct value", fontsize=19,
            weight="bold", color=INK, va="center")
    ax.text(0.2, 4.05, "VALUE SEMANTICS   /   TWO INDEPENDENT STACK SLOTS",
            fontsize=10.5, weight="bold", color=MUTED, va="center")

    panel(ax, 0.2, "1  Assignment", "var q = p")
    struct_slot(ax, 1.6, 1.52, "p", [("x", 1), ("y", 2)])
    struct_slot(ax, 4.15, 1.52, "q", [("x", 1), ("y", 2)])
    ax.add_patch(FancyArrowPatch(
        (2.58, 1.52), (3.16, 1.52), arrowstyle="-|>", mutation_scale=14,
        linewidth=1.7, color=TEAL, zorder=5))
    ax.text(2.87, 1.82, "copy value", ha="center", fontsize=10.5,
            weight="bold", color=TEAL)

    panel(ax, 6.25, "2  Mutation", "q.x = 99")
    struct_slot(ax, 7.65, 1.52, "p", [("x", 1), ("y", 2)])
    struct_slot(ax, 10.2, 1.52, "q", [("x", 99), ("y", 2)], changed_field=0)
    ax.text(7.65, 0.47, "p.x is still 1", ha="center", fontsize=11.5,
            family="monospace", color=TEAL, weight="bold")
    ax.text(10.2, 0.47, "q.x is now 99", ha="center", fontsize=11.5,
            family="monospace", color=ORANGE, weight="bold")

    fig.subplots_adjust(left=0.02, right=0.98, top=0.98, bottom=0.02)
    output = HERE / "value_semantics.png"
    fig.savefig(output, dpi=220, facecolor="white")
    plt.close(fig)
    print("wrote", output)


if __name__ == "__main__":
    make_value_semantics()
