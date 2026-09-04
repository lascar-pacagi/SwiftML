THE HEADLINE TEST: this file asks swiftc on every run, so the numbers a human wrote down in the
other files can never drift from what Swift actually prints. `make oracle F=…` does the same
for one file.

First the front end. On the 16 programs of `oracle-typecheck.txt` — nine well-formed, seven the
class rules must refuse — `swiftc -typecheck` and `./lab.exe --typecheck` must reach the same
VERDICT (it cannot judge wording, only accept-or-reject). Running programs can only exercise
what we accept; this half pins what we refuse. Only rules swiftc HAS are here: our three v0
guards (a class reference inside a struct, an enum payload or an optional) refuse programs
swiftc accepts, so they live in `sema-arc.t` with the divergence stated, not in this loop. A crash is not a rejection: exit 0 is accept, 1
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
swiftc and only type-checked by us (concept 25's loop, kept because every program here has an
initializer and half of them have two):

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
-Onone`, `swiftc -O`, `./lab.exe build`, `./lab.exe build -O` — and all four run. For this
concept that is the strongest possible test, because a `deinit` PRINTS: the corpus does not just
check what a program computes, it checks the exact moment every object dies. It is concept 26's
corpus — the twelve lifetime scenarios and then some — because the whole claim of this concept
is that recasting raw retain/release into structured ownership changes NOTHING observable, plus
three programs for what it did change: a field written through `self` (which has no slot any
more), a `+1` crossing two function boundaries while a guaranteed borrow is passed twice, and
`self` reaching a subclass override through a superclass method.

`swiftc -Onone` is the reference, and OUR two builds must match it exactly — that is the
milestone. `swiftc -O` is compared too but reported separately, because it is allowed to differ
and does: swiftc's ARC optimizer shortens lifetimes, so on two of these programs it releases
two independent objects in the other order. The order between *unrelated* objects is not part
of the language contract once the optimizer runs; the order within one deallocation, and the
moment relative to the surrounding statements, is, and that is what every other line pins. Our
own `-O` reordering anything would be a bug, and shows up as a plain DIVERGE.

A program either compiler refuses to build is reported as such, never counted as agreement; an
unstarted TODO stops the loop so the file reads TODO. (No class reference inside a struct, enum
or optional, no `print` of an aggregate, no `==` on two objects — see sema-arc.t.)

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
  >   cmp -s sw$n.out swO$n.out || printf "swiftc -O SHORTENS a lifetime in program %d (its ARC optimizer, not ours)\n" "$n"
  > done < oracle-corpus.txt
  swiftc -O SHORTENS a lifetime in program 1 (its ARC optimizer, not ours)
  swiftc -O SHORTENS a lifetime in program 14 (its ARC optimizer, not ours)
  $ echo done
  done
