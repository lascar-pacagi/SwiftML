THE HEADLINE TEST: this file asks swiftc on every run, so the numbers a human wrote down in the
other files can never drift from what Swift actually prints. `make oracle F=…` does the same
for one file.

First the front end. On the 20 programs of `typecheck-corpus.txt` — twelve well-formed, eight
the error-handling rules must refuse — `swiftc -typecheck` and `./lab.exe --typecheck` must
reach the same VERDICT (it cannot judge wording, only accept-or-reject). Only rules swiftc HAS
are here: our two v0 refusals (a throwing function returning a class, and a top-level `try`
outside a `do`) reject programs swiftc accepts, so they live in `sema-throws.t` with the
divergence stated, not in this loop. A crash is not a rejection: exit 0 is accept, 1 is reject,
anything else is a crash; on a disagreement our first line is shown, so an unstarted hole reads
as what it is.

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
exit code must be byte-identical. The twenty programs are the concept's whole story: `do`/
`catch` selecting by case and by a bare clause, three-level propagation, `try?` and `try!`,
`defer` firing LIFO at scope exit, on the throw path, inside a `do` body caught locally, and
inside a loop; throwing METHODS on a class and on a struct; a throwing function returning a
struct, an optional and nothing at all; a `deinit` that prints, so the corpus also pins that an
error edge releases what it crosses; and a `try!` that fails, whose exit CODE is the assertion.

`swiftc -Onone` is the reference and our two builds must match it. `swiftc -O` is compiled and
run too, and reported separately when it differs — it does, on exactly one program: a failing
`try!` exits 133 at `-Onone` (SIGTRAP) and 139 at `-O`, because swiftc's optimizer lowers the
unreachable failure branch differently. The stdout is empty either way. We match `-Onone` at
both of our levels, which is the contract that matters; a difference between swiftc's own two
levels is swiftc's business, and reporting it is more honest than picking whichever reference
makes us look right. A program either compiler refuses to build is reported as such, never
counted as agreement; an unstarted TODO stops the loop so the file reads TODO.

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
  swiftc -O differs from swiftc -Onone on program 9 (its optimizer, not ours)
  $ echo done
  done
