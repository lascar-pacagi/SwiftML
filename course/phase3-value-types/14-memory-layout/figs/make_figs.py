#!/usr/bin/env python3
"""figs/padding.png — struct layout: natural alignment forces padding, and field ORDER changes
the size. {Int; Bool} is 9 bytes; {Bool; Int} is 16."""
import os, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
HERE=os.path.dirname(os.path.abspath(__file__)); TEXT="#1b2733"
INT="#2f6f4f"; BOOL="#b5651d"; PAD="#d8d8d8"
def cells(ax,y,spec,title):
    ax.text(-0.4,y+0.45,title,ha="right",va="center",fontsize=10,fontweight="bold",color=TEXT)
    x=0
    for (w,c,lab) in spec:
        ax.add_patch(Rectangle((x,y),w,0.9,facecolor=c,edgecolor="#444",linewidth=1.2))
        ax.text(x+w/2,y+0.45,lab,ha="center",va="center",fontsize=8.5,color=("white" if c!=PAD else "#666"),family="monospace")
        x+=w
    for b in range(0,17,8):
        ax.plot([b,b],[y-0.15,y+1.05],color="#999",lw=0.7,ls=":")
        ax.text(b,y-0.3,str(b),ha="center",fontsize=7,color="#888")
def make():
    fig,ax=plt.subplots(figsize=(10.5,4.4)); ax.set_xlim(-3,17); ax.set_ylim(-0.7,5); ax.axis("off")
    cells(ax,3.2,[(8,INT,"i: Int"),(1,BOOL,"b"),(7,PAD,"pad → stride")],"{ Int; Bool }")
    ax.text(13.2,3.65,"size 9, stride 16",fontsize=9,color=TEXT)
    cells(ax,1.4,[(1,BOOL,"b"),(7,PAD,"pad"),(8,INT,"i: Int")],"{ Bool; Int }")
    ax.text(13.2,1.85,"size 16, stride 16",fontsize=9,color=TEXT)
    ax.text(7,4.6,"Same two fields, different order → different size. Each field lands on a multiple of its alignment.",ha="center",fontsize=10.5,fontweight="bold",color=TEXT)
    fig.tight_layout(); out=os.path.join(HERE,"padding.png"); fig.savefig(out,dpi=160,bbox_inches="tight"); plt.close(fig); print("wrote",out)
make()
