THE HEADLINE TEST: swiftc and your front end must AGREE on every program in
`oracle-corpus.txt` — functions, calls, returns, with the accept and reject cases side by side.
It cannot judge your wording, only what you accept and reject.

swiftc runs here as `-emit-sil`, not `-typecheck`: its "missing return" check is a SIL-level
diagnostic (`lib/SILOptimizer/Mandatory/DataflowDiagnostics.cpp`), so `swiftc -typecheck`
ACCEPTS a `-> Int` function that never returns, and only a stage that reaches SIL rejects it.
`-emit-sil -o /dev/null` runs the type checker and the mandatory SIL passes, and nothing after.

A crash is not a rejection: exit 0 is accept, 1 is reject, anything else is a crash. On a
disagreement the first line we printed is shown, so a rejection caused by an unfinished stage
reads as what it is:

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > p.swift
  >   if swiftc -emit-sil -o /dev/null p.swift >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --typecheck p.swift >/dev/null 2>err.txt; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || { printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"; [ $rc -eq 0 ] || { head -1 err.txt; grep -q 'TODO(' err.txt && break; }; }
  > done < oracle-corpus.txt
  $ echo done
  done
