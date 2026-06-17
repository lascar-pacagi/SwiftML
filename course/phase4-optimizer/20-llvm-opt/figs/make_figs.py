#!/usr/bin/env python3
"""Figures for 20-llvm-opt/explainer.qmd.

    .venv/bin/python phase4-optimizer/20-llvm-opt/figs/make_figs.py

Produces:
    figs/m4_bench.png — the Milestone-M4 benchmark: swiftml vs swiftc at -Onone and -O.

The numbers are a REAL run of `make bench C=phase4-optimizer/20-llvm-opt` (2026-06-09, Apple
Silicon, best-of-3 warm runs). Re-run the bench and update DATA to refresh the figure.
"""
import os
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TEXT = "#1b2733"

# bench: (swiftml -Onone, swiftml -O, swiftc -Onone, swiftc -O)  — seconds, best of 3, warm
DATA = {
    "fib": (0.055, 0.039, 0.116, 0.057),
    "collatz": (0.325, 0.093, 1.521, 0.146),
    "primes": (0.193, 0.185, 0.783, 0.170),
    "structs": (0.056, 0.013, 1.497, 0.020),
    "enums": (0.061, 0.017, 2.464, 0.019),
}
LABELS = ["swiftml -Onone", "swiftml -O", "swiftc -Onone", "swiftc -O"]
COLORS = ["#b8c4d0", "#2f6f4f", "#e3c9a8", "#b5651d"]


def make():
    benches = list(DATA.keys())
    n = len(benches)
    x = np.arange(n)
    w = 0.2

    fig, ax = plt.subplots(figsize=(11.0, 5.4))
    for i, (lab, col) in enumerate(zip(LABELS, COLORS)):
        vals = [DATA[b][i] for b in benches]
        bars = ax.bar(x + (i - 1.5) * w, vals, w, label=lab, color=col, edgecolor="#5b6b7b", linewidth=0.6)
        for r, v in zip(bars, vals):
            ax.text(r.get_x() + r.get_width() / 2, v * 1.06, f"{v:.3f}", ha="center", fontsize=6.8, color=TEXT)

    ax.set_yscale("log")
    ax.set_ylabel("runtime, seconds (log scale; lower is better)", fontsize=10)
    ax.set_xticks(x)
    ax.set_xticklabels(benches, fontsize=11)
    ax.legend(fontsize=9, ncol=4, loc="upper center", bbox_to_anchor=(0.5, 1.13), frameon=False)
    ax.grid(axis="y", alpha=0.25, which="both")
    ax.set_axisbelow(True)

    pct = [DATA[b][3] / DATA[b][1] * 100 for b in benches]
    geo = float(np.exp(np.mean(np.log(pct))))
    ax.set_title(
        f"Milestone M4 — swiftml -O runs at {geo:.0f}% of swiftc -O speed (geomean; >100% = faster).\n"
        "Caveat: swiftml omits Swift's integer-overflow traps — see the explainer's honesty section.",
        fontsize=10.5, color=TEXT, pad=34)
    fig.tight_layout()
    out = os.path.join(HERE, "m4_bench.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
