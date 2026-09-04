THE HEADLINE TEST, and Milestone M2: every program in `oracle-corpus.txt` is compiled by
`swiftc` AND by your compiler, both binaries are run, and stdout + exit code must be identical.
The other files in this directory hold numbers a human wrote down once; this one asks swiftc
on every run, so they can never drift from what Swift actually prints.

27 programs, covering everything Phase 2 can express: arithmetic and the sign rules, `Bool`
and short-circuiting, `if`/`else if`, `while`, `for`, `break`, `continue`, nests, functions,
recursion, mutual recursion, `Void` returns, and two real algorithms. It stays inside what both
compilers mean the same — no `Double` printing (Swift's float formatting is not matched in this
subset), no `print(a, b)`, and nothing above 2^62 - 1, where our lexer's OCaml `int` gives out.

A program either compiler refuses to build is reported as such, never counted as agreement; if
our refusal comes from an unfinished hole the loop stops there, so the file reads as not-started
rather than as a wall of diffs:

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
