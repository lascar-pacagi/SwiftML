THE HEADLINE TEST, four ways. Every program in `oracle-corpus.txt` is compiled by `swiftc
-Onone`, by our LLVM path (Backend A, `build`), and by our ARM64 backend (Backend B) BOTH with
the peephole pass and with `--no-peephole`; all binaries run, and stdout + exit code must be
identical. The `--no-peephole` build is the control: an optimization is only correct if the
program means the same thing with it and without it, and a peephole that forwards a stale
register produces a plausible wrong number rather than a crash.

The 32 programs are concept 35's corpus: the scalar programs, the register-pressure programs,
and the wide-call programs. They are what a peephole has to survive — every one of them reuses
variables inside a block, which is exactly the redundancy this pass rewrites, and many cross a
`bl`, which is where forwarding has to stop. A program either compiler refuses to build is
reported as such, never counted as agreement; an unstarted hole stops the loop, so the file
reads TODO rather than a wall of diffs.

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
  >   for pe in on off; do
  >     if [ $pe = off ]; then flag=--no-peephole; else flag=; fi
  >     if ! ./lab.exe build p$n.swift --native $flag -o nt$n >/dev/null 2>err.txt; then
  >       printf 'Backend B (peephole %s) REFUSED: %s\n' "$pe" "$prog"; head -1 err.txt
  >       if grep -q 'TODO(' err.txt; then echo "(stopping: the hole above is not started)"; stop=yes; fi
  >       break
  >     fi
  >     ./nt$n > nt$n.out 2>&1; ntrc=$?
  >     if [ $swrc -ne $ntrc ] || ! cmp -s sw$n.out nt$n.out; then
  >       printf 'DIVERGE B/peephole-%s (swiftc exit=%s native exit=%s): %s\n' "$pe" "$swrc" "$ntrc" "$prog"; diff sw$n.out nt$n.out
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
