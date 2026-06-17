#!/usr/bin/env python3
"""figs/abi.png — AAPCS64 argument passing & the frame. First 8 integer args in x0..x7; args 9+ on
the stack: the caller writes them to its outgoing area (just above its sp at the call), and the
callee reads them via x29 (its incoming sp), skipping the saved fp/lr. The frame pushes fp/lr first
(in-range), then allocates locals, so stp/ldp stay within their immediate range on any frame size."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = os.path.dirname(os.path.abspath(__file__))
EDGE = "#5b6b7b"; TEXT = "#1b2733"


def box(ax, x, y, w, h, lines, color, title=None, fs=8.4, ha="left"):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.03,rounding_size=0.05",
                 linewidth=1.2, edgecolor=EDGE, facecolor=color, zorder=3))
    ty = y + h - 0.28
    if title:
        ax.text(x + w / 2, ty, title, ha="center", fontsize=8.8, fontweight="bold", color=TEXT, zorder=4); ty -= 0.38
    for ln in lines:
        ax.text(x + (0.16 if ha == "left" else w / 2), ty, ln, ha=ha, fontsize=fs, family="monospace", color=TEXT, zorder=4); ty -= 0.32


def arr(ax, p0, p1, color="#b5651d", label=None, dx=0, dy=0.12):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=11, linewidth=1.6, color=color, zorder=5))
    if label:
        ax.text((p0[0] + p1[0]) / 2 + dx, (p0[1] + p1[1]) / 2 + dy, label, ha="center", fontsize=8, color=color, fontweight="bold", zorder=6)


def make():
    fig, ax = plt.subplots(figsize=(12.8, 6.6))
    ax.set_xlim(0, 13); ax.set_ylim(0, 7.4); ax.axis("off")
    ax.text(6.5, 7.15, "AAPCS64: first 8 args in registers, the rest on the stack — and a frame that works at any size",
            ha="center", fontsize=11.6, fontweight="bold", color=TEXT)

    # the call: arg classification
    box(ax, 0.3, 4.7, 5.6, 2.2,
        ["f(a1..a10):", "  a1..a8  -> x0..x7  (registers)",
         "  a9, a10 -> the STACK", "", "caller: str x?, [sp, #0] ; a9", "        str x?, [sp, #8] ; a10"],
        "#eef2f7", title="argument classification (caller side)")

    # the callee frame
    box(ax, 6.4, 0.5, 6.3, 6.4,
        ["[x29+24] a10        <- incoming stack args", "[x29+16] a9             (above the frame record)",
         "[x29+8]  saved lr (x30)", "[x29+0]  saved fp (x29)  <- x29 points here",
         "  ----  (sub sp, #locals)  ----", "[sp+..]  callee-saved x19..x27",
         "[sp+..]  value slots / spills", "[sp+0]   outgoing area (for ITS calls)"],
        "#e8f6ee", title="callee frame  (grows downward)")
    arr(ax, (5.9, 5.6), (6.4, 6.0), label="x0..x7")
    arr(ax, (5.9, 5.0), (6.4, 6.45), label="[sp,#0/8] -> [x29,#16/24]", dx=0.2, dy=0.2)

    box(ax, 0.3, 1.7, 5.6, 2.6,
        ["prologue (large-frame-safe):", "  sub  sp, sp, #16",
         "  stp  x29, x30, [sp, #0]   <- offset 0, always in range",
         "  mov  x29, sp              <- x29 = frame record",
         "  sub  sp, sp, #locals      <- THEN the big allocation",
         "callee reads a9 at [x29, #16], a10 at [x29, #24]"],
        "#fff8e1", title="the frame record first, locals second")
    box(ax, 0.3, 0.5, 5.6, 1.0,
        ["concepts 33-34 put stp at [sp, #frame-16] -- a 12-arg",
         "function overflowed that immediate. push-then-sub fixes it."],
        "#fdeded", title="the bug this fixes")

    fig.tight_layout()
    out = os.path.join(HERE, "abi.png")
    fig.savefig(out, dpi=160, bbox_inches="tight"); plt.close(fig); print("wrote", out)


make()
