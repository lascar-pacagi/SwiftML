THE HEADLINE TEST: swiftc and your compiler must AGREE on every program in
`oracle-corpus.txt` — the control-flow subset again, now all the way down to SIL, with the
accept and reject cases side by side. It cannot judge the SIL you emit, only what you accept
and what you refuse; the shape is what the `silgen-*.t` files are for.

swiftc runs as `-emit-sil -o /dev/null`, the same stage we stop at: the type checker plus the
mandatory SIL passes, and nothing after. That matters because "missing return" is a SIL-level
diagnostic (`lib/SILOptimizer/Mandatory/DataflowDiagnostics.cpp`), so `swiftc -typecheck`
accepts a `-> Int` function that falls off the end and three reject cases would disagree.

swiftc and your `--emit-sil` agree on all 34 corpus programs, twenty accepted and fourteen
refused. A crash is not a rejection: exit 0 is accept, 1 is reject, anything else is a crash.
On a disagreement the first line we printed is shown, so a rejection that is really an
unlowered statement reads as what it is, and the loop stops there:

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > p.swift
  >   if swiftc -emit-sil -o /dev/null p.swift >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --emit-sil p.swift >/dev/null 2>err.txt; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || { printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"; [ $rc -eq 0 ] || { head -1 err.txt; grep -q 'TODO(' err.txt && break; }; }
  > done < oracle-corpus.txt
  $ echo done
  done
