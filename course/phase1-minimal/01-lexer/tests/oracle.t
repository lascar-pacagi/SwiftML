The lexical decisions this concept makes are checked AGAINST SWIFTC, every run.

The comment-nesting rule is the one people get wrong, and the goldens in `lexer.t` only record
what swiftc said on the day they were written. This asks again: for each program in
`oracle-corpus.txt`, `swiftc -typecheck` and `./lab.exe --emit-tokens` must agree on whether it
is lexable — `/*/**/*/` is a complete comment, `/*/*/` is not, and so on. (The corpus is written
so that every program is otherwise legal Swift, so the only thing that can reject it is the
lexer.) Digit separators (`1_000`) are deliberately NOT here: they are §6 exercise 1, and an
oracle line whose verdict depends on an optional exercise would be a golden that is right for
some learners and wrong for others.

A crash is not a rejection: exit 0 is accept, 1 is reject, anything else is reported as a crash.

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > p.swift
  >   if swiftc -typecheck p.swift >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --emit-tokens p.swift >/dev/null 2>&1; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"
  > done < oracle-corpus.txt
  $ echo done
  done
