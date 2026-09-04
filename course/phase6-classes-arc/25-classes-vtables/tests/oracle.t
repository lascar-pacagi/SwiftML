THE HEADLINE TEST: this file asks swiftc on every run, so the numbers a human wrote down in the
other files can never drift from what Swift actually prints. `make oracle F=…` does the same
for one file.

First the front end. On the 22 programs of `oracle-typecheck.txt` — ten well-formed, twelve the
class rules must refuse — `swiftc -typecheck` and `./lab.exe --typecheck` must reach the same
VERDICT (it cannot judge wording, only accept-or-reject). Running programs can only exercise
what we accept; this half pins what we refuse. A crash is not a rejection: exit 0 is accept, 1
is reject, anything else is a crash; on a disagreement our first line is shown, so an unstarted
hole reads as what it is.

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > t.swift
  >   if swiftc -typecheck t.swift >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --typecheck t.swift >/dev/null 2>err.txt; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || { printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"; [ $rc -eq 0 ] || { head -1 err.txt; grep -q 'TODO(' err.txt && break; }; }
  > done < oracle-typecheck.txt
  $ echo done
  done

Then definite initialization, which needs a different reference command. swiftc runs DI at the
SIL level, so `swiftc -typecheck` accepts an initializer that leaves a property unset; only a
FULL compile reports it. The six programs of `oracle-di.txt` — three that DI must refuse, three
that are fine, including the implicit `super.init()` — are therefore compiled all the way by
swiftc and only type-checked by us:

  $ while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue
  >   printf '%b\n' "$prog" > d.swift
  >   if swiftc -Onone d.swift -o dsw >/dev/null 2>&1; then sw=accept; else sw=reject; fi
  >   ./lab.exe --typecheck d.swift >/dev/null 2>err.txt; rc=$?
  >   case $rc in 0) ml=accept;; 1) ml=reject;; *) ml="crash($rc)";; esac
  >   [ "$sw" = "$ml" ] || { printf 'DISAGREE  swiftc=%s ours=%s  %s\n' "$sw" "$ml" "$prog"; [ $rc -eq 0 ] || { head -1 err.txt; grep -q 'TODO(' err.txt && break; }; }
  > done < oracle-di.txt
  $ echo done
  done

Then the whole pipeline. Every program in `oracle-corpus.txt` is compiled FOUR ways — `swiftc
-Onone`, `swiftc -O`, `./lab.exe build`, `./lab.exe build -O` — all four binaries run, and
stdout + exit code must be identical to `swiftc -Onone`'s. The 18 programs are everything this
concept adds: reference semantics and shared mutation, an override replacing a slot, dispatch
through a superclass-typed variable and through a superclass's own method, a three-level
hierarchy, `super.init` chains, an inherited initializer, the implicit `super.init()`, a `let`
property, objects made in a loop, classes holding a struct / an enum / an optional / an
existential, classes passed to and returned from functions, a class that builds another
instance of itself, and a Double field. Only stdout and the exit code are compared. A program
either compiler refuses to build is reported as such, never counted as agreement; an unstarted
TODO stops the loop so the file reads TODO. (No `print` of an aggregate, no `==` on two
objects, no `===`, no class downcast — see sema-classes.t.)

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
