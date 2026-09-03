THE HEADLINE TEST: `swiftc -typecheck` and your checker must AGREE on every program in
`oracle-corpus.txt`. The corpus is syntactically fine Swift, so only sema decides; it avoids
what the two differ on by design (print's arity — Swift's is variadic — and redeclaration,
which is a §6 exercise). It cannot judge your wording, only what you accept and reject.

A crash is not a rejection: exit 0 is accept, 1 is reject, anything else is reported as a crash.

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > p.swift
  >   if swiftc -typecheck p.swift >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --typecheck p.swift >/dev/null 2>&1; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"
  > done < oracle-corpus.txt
  $ echo done
  done
