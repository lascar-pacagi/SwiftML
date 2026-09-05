THE HEADLINE TEST, in two halves — because this concept is a compile-time rule with a runtime
that is unchanged, and the two need different oracles.

First the front end. On the 18 programs of `typecheck-corpus.txt` — nine well formed, nine the
isolation rule must refuse — `swiftc -typecheck` and `./lab.exe --typecheck` must reach the same
VERDICT. Each rejected program is paired with the awaited version of itself, so the corpus is
not testing "does it say no" but "does it say no to exactly the right half". Exit 0 is accept, 1
is reject, anything else is a crash; on a disagreement our first line is shown, and an unstarted
hole stops the loop.

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

Then the whole pipeline. The 10 programs of `oracle-corpus.txt` are compiled by `swiftc -Onone`,
`swiftc -O` and our build at `-Onone` and `-O`, all run, stdout and exit code byte-identical.
They are the runtime claim: an actor IS a class, so its state, its methods, its `self`-calls, its
optionals and arrays and recursion all behave exactly as concept 25's objects do. Every call
crosses the isolation boundary with `await`, which is what makes them comparable — a serial
executor and a concurrent one agree whenever the program has only one thing to do at a time.

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
  >     printf 'ours -O REFUSED: %s\n' "$prog"; head -1 err.txt; continue
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
