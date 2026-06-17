#!/usr/bin/env python3
"""Figures for 24-specialization/explainer.qmd.

    .venv/bin/python phase5-generics/24-specialization/figs/make_figs.py

Produces:
    figs/m5_bench.png — the Milestone-M5 benchmark: generic/existential hot loops, swiftml vs
    swiftc at -Onone and -O. The numbers are a REAL run of
    `make bench C=phase5-generics/24-specialization` (2026-06-11, Apple Silicon, best-of-3
    warm runs). Re-run the bench and update DATA to refresh.
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
    "genloop\n(generic 30M)": (0.159, 0.089, 1.964, 0.090),
    "exloop\n(existential 10M)": (0.064, 0.030, 0.674, 0.032),
    "maxgen\n(biggest<T> 8M)": (0.050, 0.011, 0.735, 0.012),
}
LABELS = ["swiftml -Onone", "swiftml -O", "swiftc -Onone", "swiftc -O"]
COLORS = ["#b8c4d0", "#2f6f4f", "#e3c9a8", "#b5651d"]


def make():
    benches = list(DATA.keys())
    x = np.arange(len(benches))
    w = 0.2
    fig, ax = plt.subplots(figsize=(10.6, 5.2))
    for i, (lab, col) in enumerate(zip(LABELS, COLORS)):
        vals = [DATA[b][i] for b in benches]
        bars = ax.bar(x + (i - 1.5) * w, vals, w, label=lab, color=col, edgecolor="#5b6b7b", linewidth=0.6)
        for r, v in zip(bars, vals):
            ax.text(r.get_x() + r.get_width() / 2, v * 1.07, f"{v:.3f}", ha="center", fontsize=7, color=TEXT)
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
        f"Milestone M5 — specialization + devirtualization erase the abstraction: swiftml -O = {geo:.0f}% of swiftc -O\n"
        "(swiftc -Onone pays up to 60× for unoptimized protocol dispatch + ARC; our -Onone only pays the witness calls)",
        fontsize=10, color=TEXT, pad=36)
    fig.tight_layout()
    out = os.path.join(HERE, "m5_bench.png")
    fig.savefig(out, dpi=160, bbox_inches="tight")
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    make()
