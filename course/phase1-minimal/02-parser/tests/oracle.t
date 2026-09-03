THE HEADLINE TEST: `swiftc` and this parser must AGREE on what is syntactically well-formed.

Every golden in the other files records what was true when it was written; this asks swiftc
again, on each program in `oracle-corpus.txt`, and fails if the two ever disagree. The corpus is
written so that every program is otherwise legal Swift — names declared, one argument to print —
so the only thing that can reject a line is its syntax. It cannot tell you your MESSAGE is right
(that wording is yours), only that you accept and reject the same programs swiftc does.

A crash is not a rejection: exit 0 is accept, 1 is reject, anything else is reported as a crash.

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > p.swift
  >   if swiftc -typecheck p.swift >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --emit-ast p.swift >/dev/null 2>err.txt; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || { printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"; [ $rc -le 1 ] || { head -1 err.txt; grep -q 'TODO(' err.txt && break; }; }
  > done < oracle-corpus.txt
  $ echo done
  done
