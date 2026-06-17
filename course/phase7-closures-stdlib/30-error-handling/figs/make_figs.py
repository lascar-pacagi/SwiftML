#!/usr/bin/env python3
"""figs/errordesugar.png — error handling as PURE DESUGARING: throw/try/do-catch all lower to
ordinary branches + the @swiftml.error register. No new SIL instruction."""
import os, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
HERE=os.path.dirname(os.path.abspath(__file__)); EDGE="#5b6b7b"; TEXT="#1b2733"
SRC="#eef2f7"; REG="#fff3d6"; CF="#dceede"
def box(ax,x,y,w,h,lines,color,title=None,fs=8.2):
    ax.add_patch(FancyBboxPatch((x,y),w,h,boxstyle="round,pad=0.04,rounding_size=0.07",linewidth=1.3,edgecolor=EDGE,facecolor=color,zorder=3))
    ty=y+h-0.34
    if title: ax.text(x+w/2,ty,title,ha="center",fontsize=9.2,fontweight="bold",color=TEXT,zorder=4); ty-=0.42
    for ln in lines: ax.text(x+w/2,ty,ln,ha="center",fontsize=fs,family="monospace",color=TEXT,zorder=4); ty-=0.36
def arr(ax,p0,p1,label=None,dx=0,dy=0):
    ax.add_patch(FancyArrowPatch(p0,p1,arrowstyle="-|>",mutation_scale=13,linewidth=1.7,color="#b5651d",zorder=5))
    if label: ax.text((p0[0]+p1[0])/2+dx,(p0[1]+p1[1])/2+dy,label,ha="center",fontsize=8.4,color="#b5651d",fontweight="bold",zorder=6)
def make():
    fig,ax=plt.subplots(figsize=(11.8,6.0)); ax.set_xlim(0,13); ax.set_ylim(0,7); ax.axis("off")
    box(ax,0.3,3.9,4.0,2.6,["throw E.divByZero","","x = try f(a, b)","","do { … } catch P { … }"],SRC,title="source (sugar)")
    box(ax,5.0,4.4,3.0,2.1,["= 0  no error","= 7  divByZero","= 8  negative"],REG,title="@swiftml.error (one Int)")
    box(ax,9.0,3.7,3.8,2.9,["throw  -> error_set(7); ret default","","try f -> %e = error_get()","         if %e != 0: goto handler","","do/catch -> compare %e to ordinals"],CF,title="desugared (branches + 2 rt calls)")
    arr(ax,(4.4,5.2),(4.95,5.2),label="set/get")
    arr(ax,(8.05,5.2),(8.95,5.2),label="branch")
    ax.text(6.5,0.7,"Zero new SIL instructions — error propagation is an Int register + a conditional branch (swiftc passes it in x21).",ha="center",fontsize=9.4,color="#444",style="italic")
    ax.text(6.5,6.8,"Error handling = pure desugaring: throw / try / do-catch / try? / try! / defer over one error register",ha="center",fontsize=11,fontweight="bold",color=TEXT)
    fig.tight_layout(); out=os.path.join(HERE,"errordesugar.png"); fig.savefig(out,dpi=160,bbox_inches="tight"); plt.close(fig); print("wrote",out)
make()
