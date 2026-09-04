THE HEADLINE TEST, three ways. Every program in `oracle-corpus.txt` is compiled by `swiftc`, by
our LLVM path (Backend A, `build`) and by our ARM64 backend (Backend B, `build --native`); all
three binaries run, and stdout + exit code must be identical. `make oracle F=…` does this for
one file; this does it for the corpus on every run.

A program either compiler refuses to build is reported as such, never counted as agreement. The
corpus is Backend B's v0 subset — Int/Bool, arithmetic, comparisons, control flow, functions of
up to eight arguments, print — and stays inside what both compilers mean the same (no overflow,
no division by zero, literals below 2^62).

  $ n=0; while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue; n=$((n+1))
  >   printf '%b\n' "$prog" > p$n.swift
  >   if ! swiftc -Onone p$n.swift -o sw$n >/dev/null 2>&1; then printf 'swiftc REFUSED: %s\n' "$prog"; continue; fi
  >   if ! ./lab.exe build p$n.swift -o ml$n >/dev/null 2>err.txt; then printf 'Backend A REFUSED: %s\n' "$prog"; head -1 err.txt; continue; fi
  >   if ! ./lab.exe build p$n.swift --native -o nt$n >/dev/null 2>err.txt; then
  >     printf 'Backend B REFUSED: %s\n' "$prog"; head -1 err.txt
  >     if grep -q 'TODO(' err.txt; then echo "(stopping: the hole above is not started)"; break; fi
  >     continue
  >   fi
  >   ./sw$n > sw$n.out 2>&1; swrc=$?
  >   ./ml$n > ml$n.out 2>&1; mlrc=$?
  >   ./nt$n > nt$n.out 2>&1; ntrc=$?
  >   if [ $swrc -ne $mlrc ] || ! cmp -s sw$n.out ml$n.out; then
  >     printf 'DIVERGE A (swiftc exit=%s ours exit=%s): %s\n' "$swrc" "$mlrc" "$prog"; diff sw$n.out ml$n.out
  >   fi
  >   if [ $swrc -ne $ntrc ] || ! cmp -s sw$n.out nt$n.out; then
  >     printf 'DIVERGE B (swiftc exit=%s native exit=%s): %s\n' "$swrc" "$ntrc" "$prog"; diff sw$n.out nt$n.out
  >   fi
  > done < oracle-corpus.txt
  $ echo done
  done
