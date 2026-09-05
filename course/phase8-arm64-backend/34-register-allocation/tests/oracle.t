THE HEADLINE TEST, three ways and three rungs. Every program in `oracle-corpus.txt` is compiled
by `swiftc -Onone`, by our LLVM path (Backend A, `build`) and by our ARM64 backend (Backend B,
`build --native`) under EACH of the three allocators; all binaries run, and stdout + exit code
must be identical. Allocation is the stage where a wrong answer is silent — a value in the
wrong register still prints a number — so agreement across the whole ladder is the real proof
that `linscan` and `graphcolor` only changed WHERE values live, never what the program means.

The 26 programs are concept 33's scalar corpus plus five written for register pressure: twelve
simultaneously-live `let`s, ten loop-carried variables, a function holding six live temporaries
at once, a recursion that keeps three values live across its own call, and a forty-`let` main
whose frame runs past a kilobyte (the case the old prologue could not assemble). A program
either compiler refuses to build is reported as such, never counted as agreement; an unstarted
hole stops the loop, so the file reads TODO rather than a wall of diffs.

  $ n=0; while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue; n=$((n+1))
  >   printf '%b\n' "$prog" > p$n.swift
  >   if ! swiftc -Onone p$n.swift -o sw$n >/dev/null 2>&1; then printf 'swiftc REFUSED: %s\n' "$prog"; continue; fi
  >   if ! ./lab.exe build p$n.swift -o ml$n >/dev/null 2>err.txt; then printf 'Backend A REFUSED: %s\n' "$prog"; head -1 err.txt; continue; fi
  >   ./sw$n > sw$n.out 2>&1; swrc=$?
  >   ./ml$n > ml$n.out 2>&1; mlrc=$?
  >   if [ $swrc -ne $mlrc ] || ! cmp -s sw$n.out ml$n.out; then
  >     printf 'DIVERGE A (swiftc exit=%s ours exit=%s): %s\n' "$swrc" "$mlrc" "$prog"; diff sw$n.out ml$n.out
  >   fi
  >   stop=no
  >   for r in stack linscan graphcolor; do
  >     if ! ./lab.exe build p$n.swift --native --regalloc=$r -o nt$n >/dev/null 2>err.txt; then
  >       printf 'Backend B (%s) REFUSED: %s\n' "$r" "$prog"; head -1 err.txt
  >       if grep -q 'TODO(' err.txt; then echo "(stopping: the hole above is not started)"; stop=yes; fi
  >       break
  >     fi
  >     ./nt$n > nt$n.out 2>&1; ntrc=$?
  >     if [ $swrc -ne $ntrc ] || ! cmp -s sw$n.out nt$n.out; then
  >       printf 'DIVERGE B/%s (swiftc exit=%s native exit=%s): %s\n' "$r" "$swrc" "$ntrc" "$prog"; diff sw$n.out nt$n.out
  >     fi
  >   done
  >   [ $stop = yes ] && break
  > done < oracle-corpus.txt
  [1]
  $ echo done
  done

A multi-line `[ … ]` literal is one expression, not four statements — the shared front end
carried into Phase 8. Arrays are outside Backend B's v0 scope, so this one is checked two ways,
against `swiftc` and against Backend A.

  $ printf 'let xs = [\n  10,\n  20,\n  30\n]\nprint(xs.count)\nprint(xs[1])\n' > multi.swift
  $ swiftc -Onone multi.swift -o swmulti && ./swmulti
  3
  20
  $ ./lab.exe build multi.swift -o mlmulti && ./mlmulti
  3
  20
