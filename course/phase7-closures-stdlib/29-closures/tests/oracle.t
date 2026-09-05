THE HEADLINE TEST: this file asks swiftc on every run, so the numbers a human wrote down in the
other files can never drift from what Swift actually prints. `make oracle F=…` does the same
for one file.

First the front end. On the 20 programs of `typecheck-corpus.txt` — eight well-formed, twelve
the type rules must refuse — `swiftc -typecheck` and `./lab.exe --typecheck` must reach the same
VERDICT (it cannot judge wording, only accept-or-reject). Only rules swiftc HAS are here: our
three v0 refusals (capturing a class, calling a captured function value, printing an aggregate)
reject programs swiftc accepts, so they live in `sema-captures.t` with the divergence stated,
not in this loop. A crash is not a rejection: exit 0 is accept, 1 is reject, anything else is a
crash; on a disagreement our first line is shown, so an unstarted hole reads as what it is.

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > t.swift
  >   if swiftc -typecheck t.swift >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --typecheck t.swift >/dev/null 2>err.txt; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || { printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"; [ $rc -eq 0 ] || { head -1 err.txt; grep -q 'TODO(' err.txt && break; }; }
  > done < typecheck-corpus.txt
  $ echo done
  done

Then the whole pipeline. Every program in `oracle-corpus.txt` is compiled FOUR ways — `swiftc
-Onone`, `swiftc -O`, `./lab.exe build`, `./lab.exe build -O` — and all four run; stdout and
exit code must be byte-identical. The twenty programs are the concept's whole story: closure
literals of every result type, higher-order functions taking a named function and a literal,
independent adder contexts, a reassigned function-typed `var`, struct and enum and optional
captures, closures created inside a loop, a closure built in each arm of an `if`, and the ARC
probe where a `Box` dies at scope exit because the closure captured `b.v`'s Int rather than `b`
— the one program whose output pins WHEN something happens rather than what it computes.

`swiftc -Onone` is the reference and our two builds must match it; `swiftc -O` is compared too
and reported separately, because it is allowed to differ (it does not, on this corpus). A
program either compiler refuses to build is reported as such, never counted as agreement; an
unstarted TODO stops the loop so the file reads TODO.

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
  >   for b in ml mlO; do
  >     sh -c "./$b$n; echo exit=\$?" > $b$n.out 2>/dev/null
  >     if ! cmp -s sw$n.out $b$n.out; then
  >       case $b in ml) who='ours -Onone';; mlO) who='ours -O';; esac
  >       printf 'DIVERGE (%s vs swiftc -Onone): %s\n' "$who" "$prog"; diff sw$n.out $b$n.out
  >     fi
  >   done
  >   sh -c "./swO$n; echo exit=\$?" > swO$n.out 2>/dev/null
  >   cmp -s sw$n.out swO$n.out || printf "swiftc -O differs from swiftc -Onone on program %d (its optimizer, not ours)\n" "$n"
  > done < oracle-corpus.txt
  $ echo done
  done
