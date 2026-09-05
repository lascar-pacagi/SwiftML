THE HEADLINE TEST, three ways and three rungs. Every program in `oracle-corpus.txt` is compiled
by `swiftc -Onone`, by our LLVM path (Backend A, `build`) and by our ARM64 backend (Backend B,
`build --native`) under EACH of the three allocators; all binaries run, and stdout + exit code
must be identical. An ABI bug is silent in the same way an allocation bug is — a wide call that
reads the wrong stack word still returns a number — and it is also *asymmetric*: the caller and
the callee are different functions, so only running them together proves they agree.

The 32 programs are concept 34's corpus plus six that cross the eight-register boundary this
concept is about: a ten-argument sum, a twelve-argument weighted sum, a ten-argument function
called in a loop, a ten-argument RECURSION (every level writes the outgoing area its caller just
used), a program mixing wide and narrow calls with wide calls as arguments to each other, and a
FOURTEEN-argument call inside a loop — six outgoing words, so the spill homes had better not sit
in them. A
program either compiler refuses to build is reported as such, never counted as agreement; an
unstarted hole stops the loop, so the file reads TODO rather than a wall of diffs.

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
