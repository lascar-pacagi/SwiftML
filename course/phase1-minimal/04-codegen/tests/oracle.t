THE HEADLINE TEST: the Phase-1 milestone. Every program in `oracle-corpus.txt` is compiled by
`swiftc` AND by your compiler, both binaries run, and stdout + exit code must be identical.
`make oracle F=…` does this for one file; this does it for the corpus on every run, so the
numbers in the other files can never drift from what swiftc actually prints.

A program either compiler refuses to build is reported as such, never counted as agreement.
(The corpus stops at 2^62 - 1: our lexer stores literals in an OCaml `int`, 63 bits, and
crashes above that — Swift's Int is 64 bits. Known gap, PROOFREAD.md.)

  $ n=0; while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue; n=$((n+1))
  >   printf '%b\n' "$prog" > p$n.swift
  >   if ! swiftc -Onone p$n.swift -o sw$n >/dev/null 2>&1; then printf 'swiftc REFUSED: %s\n' "$prog"; continue; fi
  >   if ! ./lab.exe build p$n.swift -o ml$n >/dev/null 2>err.txt; then
  >     printf 'ours REFUSED: %s\n' "$prog"; head -1 err.txt
  >     if grep -q 'TODO(' err.txt; then echo "(stopping: the hole above is not started)"; break; fi
  >     continue
  >   fi
  >   ./sw$n > sw$n.out 2>&1; swrc=$?
  >   ./ml$n > ml$n.out 2>&1; mlrc=$?
  >   if [ $swrc -ne $mlrc ] || ! cmp -s sw$n.out ml$n.out; then
  >     printf 'DIVERGE (swiftc exit=%s ours exit=%s): %s\n' "$swrc" "$mlrc" "$prog"; diff sw$n.out ml$n.out
  >   fi
  > done < oracle-corpus.txt
  $ echo done
  done
