THE HEADLINE TEST: this file asks swiftc on every run, so the numbers a human wrote down in
the other files can never drift from what Swift actually prints. `make oracle F=…` does the
same for one file. A program either compiler refuses is reported as such, never counted as
agreement; when our refusal comes from an unfinished hole the loop stops there, so the file
reads as not-started rather than as a wall of diffs.

The 16 programs of `oracle-corpus.txt` are built by `swiftc -Onone` AND by `./lab.exe build`,
both binaries are run, and stdout + exit code must be identical. They are everything an enum
can do before `switch` arrives: tag equality, `!=`, implicit raw values in declaration order,
enums in `var`s, `if`s and loops, enums into and out of functions, enums beside structs, and
associated-value cases built and passed around. (`print` of an enum stays out: swiftc prints
the case name through reflection, we refuse it — the divergence of §2.)

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

The front-end half: on the 18 programs of `typecheck-corpus.txt` — six well-formed, twelve the
enum rules must refuse — `swiftc -typecheck` and `./lab.exe --typecheck` must reach the same
verdict. Running programs can only exercise what we accept; this half pins what we refuse, and
it needs no lowering, so it is green from the skeleton. A crash is not a rejection: exit 0 is
accept, 1 is reject, anything else is a crash. (The two rules where we are stricter than swiftc
stay out of it: `print` of an enum, and `E.a` naming a payload case with no arguments — swiftc
reads that as the case's constructor *function*, a value our subset has no type for.)

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
