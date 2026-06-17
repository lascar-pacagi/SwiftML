#!/usr/bin/env python3
"""Figures for 28-arc-optimization/explainer.qmd.

    .venv/bin/python phase6-classes-arc/28-arc-optimization/figs/make_figs.py

Produces:
    figs/m6_bench.png — the Milestone-M6 benchmark: borrow-copy-heavy class loops, swiftml vs
    swiftc at -Onone and -O. Numbers from a REAL run of
    `make bench C=phase6-classes-arc/28-arc-optimization` (2026-06-12, Apple Silicon,
    best-of-3 warm runs). Re-run the bench and update DATA to refresh.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TEXT = "#1b2733"

# bench: (swiftml -Onone, swiftml -O, swiftc -Onone, swiftc -O) — seconds, best of 3, warm
DATA = {
    "borrowloop\n(copy/destroy ×30M)": (0.062, 0.009, 2.108, 0.012),
    "handoff\n(3 chained copies ×20M)": (0.105, 0.053, 1.455, 0.059),
}
LABELS = ["swiftml -Onone", "swiftml -O", "swiftc -Onone", "swiftc -O"]
COLORS = ["#b8c4d0", "#2f6f4f", "#e3c9a8", "#b5651d"]


def make():
    benches = list(DATA.keys())
    x = np.arange(len(benches))
    w = 0.2
    fig, ax = plt.subplots(figsize=(9.6, 5.2))
    for i, (lab, col) in enumerate(zip(LABELS, COLORS)):
        vals = [DATA[b][i] for b in benches]
        bars = ax.bar(x + (i - 1.5) * w, vals, w, label=lab, color=col, edgecolor="#5b6b7b", linewidth=0.6)
        for r, v in zip(bars, vals):
            ax.text(r.get_x() + r.get_width() / 2, v * 1.07, f"{v:.3f}", ha="center", fontsize=7.4, color=TEXT)
    ax.set_yscale("log")
    ax.set_ylabel("runtime, seconds (log; lower is better)", fontsize=10)
    ax.set_xticks(x)
    ax.set_xticklabels(benches, fontsize=9.5)
    ax.legend(fontsize=9, ncol=4, loc="upper center", bbox_to_anchor=(0.5, 1.14), frameon=False)
    ax.grid(axis="y", alpha=0.25, which="both")
    ax.set_axisbelow(True)
    pct = [DATA[b][3] / DATA[b][1] * 100 for b in benches]
    geo = float(np.exp(np.mean(np.log(pct))))
    ax.set_title(
        f"Milestone M6 — copy propagation + WMO devirt erase the ARC traffic: swiftml -O = {geo:.0f}% of swiftc -O\n"
        "(borrowloop: 30M retain/release pairs deleted, 6.9× over our -Onone; swiftc -Onone pays its full ARC+dispatch cost)",
        fontsize=9.6, color=TEXT, pad=36)
    fig.tight_layout()
    out = os.path.join(HERE, "m6_bench.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
