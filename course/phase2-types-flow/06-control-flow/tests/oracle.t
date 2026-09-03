THE HEADLINE TEST: `swiftc -typecheck` and your front end must AGREE on every program in
`oracle-corpus.txt` — the control-flow subset, with its accept and reject cases side by side.
It cannot judge your wording, only what you accept and reject.

A crash is not a rejection: exit 0 is accept, 1 is reject, anything else is a crash. On a
disagreement the first line we printed is shown, so a rejection caused by an unfinished stage
(an `invalid character` from a lexer that does not know `{` yet) reads as what it is:

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > p.swift
  >   if swiftc -typecheck p.swift >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --typecheck p.swift >/dev/null 2>err.txt; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || { printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"; [ $rc -eq 0 ] || { head -1 err.txt; grep -q 'TODO(' err.txt && break; }; }
  > done < oracle-corpus.txt
  $ echo done
  done
