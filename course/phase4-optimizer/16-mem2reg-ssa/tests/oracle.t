THE HEADLINE TEST: the optimizer's invariant. Every program in `oracle-corpus.txt` is compiled
FOUR ways — `swiftc -Onone`, `swiftc -O`, `./lab.exe build`, `./lab.exe build -O` — all four
binaries run, and stdout + exit code must be identical to `swiftc -Onone`'s. A pass that
changes what a program prints is a bug, not an optimization, and this is where it shows.

The corpus is control-flow-heavy on purpose, because that is what renaming can get wrong: loops
with side effects, recursion, nested loops with `break`/`continue`, an `if`/`else` inside a loop
that writes two variables on both arms (two header arguments, four incoming edges), a `let`
declared *inside* a loop body (the case pruned SSA exists for — a spurious header argument there
has no reaching value on the entry edge), structs, enums and `switch`, optionals, and a
force-unwrap of nil whose exit 133 must survive `-O`. Three of the twenty pin the front-end
fixes this concept carries: an optional stored property written with `nil` and then with a
value, a `let` property read beside a `var` one, and a `Double` field times an integer literal.
Only stdout and the exit code are compared: swiftc's trap message names the file and line at
`-Onone` and is dropped at `-O`, so stderr is not a parity target.

A program either compiler refuses to build is reported as such, never counted as agreement; an
unstarted TODO stops the loop so the file reads TODO. (No `print(a, b)`, no ÷0 — that is
undefined in our IR where swiftc traps, see PROOFREAD.md — no literal above 2^62.)

  $ n=0; while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue; n=$((n+1))
  >   printf '%b\n' "$prog" > p$n.swift
  >   if ! swiftc -Onone p$n.swift -o sw$n >/dev/null 2>&1; then printf 'swiftc REFUSED: %s\n' "$prog"; continue; fi
  >   swiftc -O p$n.swift -o swO$n >/dev/null 2>&1
  >   if ! ./lab.exe build p$n.swift -o ml$n >/dev/null 2>err.txt; then
  >     printf 'ours REFUSED: %s\n' "$prog"; head -1 err.txt
  >     if grep -q 'TODO(' err.txt; then echo "(stopping: the hole above is not started)"; break; fi
  >     continue
  >   fi
  >   if ! ./lab.exe build p$n.swift -O -o mlO$n >/dev/null 2>err.txt; then
  >     printf 'ours -O REFUSED: %s\n' "$prog"; head -1 err.txt
  >     if grep -q 'TODO(' err.txt; then echo "(stopping: the hole above is not started)"; break; fi
  >     continue
  >   fi
  >   sh -c "./sw$n; echo exit=\$?" > sw$n.out 2>/dev/null
  >   for b in swO ml mlO; do
  >     sh -c "./$b$n; echo exit=\$?" > $b$n.out 2>/dev/null
  >     if ! cmp -s sw$n.out $b$n.out; then
  >       case $b in swO) who='swiftc -O';; ml) who='ours -Onone';; mlO) who='ours -O';; esac
  >       printf 'DIVERGE (%s vs swiftc -Onone): %s\n' "$who" "$prog"; diff sw$n.out $b$n.out
  >     fi
  >   done
  > done < oracle-corpus.txt
  $ echo done
  done
