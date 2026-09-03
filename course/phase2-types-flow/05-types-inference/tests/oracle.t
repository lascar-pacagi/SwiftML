THE HEADLINE TEST: `swiftml` and `swiftc` must AGREE on accept/reject.

Every other test freezes a golden — what swiftc printed on the day it was written. This one asks
swiftc again, on each program in `oracle-corpus.txt`, and fails if the two compilers ever disagree.
It is the only test here that cannot go stale.

A CRASH is not a rejection: `failwith "TODO"` and `assert false` also exit non-zero, and counting
them as "reject" would let an unfinished checker agree with swiftc by accident on every invalid
program. Exit 0 is accept, 1 is reject, anything else is reported as a crash.

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
