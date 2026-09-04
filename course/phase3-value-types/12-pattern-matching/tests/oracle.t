THE HEADLINE TEST: this file asks swiftc on every run, so the numbers a human wrote down in
the other files can never drift from what Swift actually prints. `make oracle F=…` does the
same for one file. A program either compiler refuses is reported as such, never counted as
agreement; when our refusal comes from an unfinished hole the loop stops there, so the file
reads as not-started rather than as a wall of diffs.

The 16 programs of `oracle-corpus.txt` are built by `swiftc -Onone` AND by `./lab.exe build`,
both binaries are run, and stdout + exit code must be identical. They are what `switch` is for:
destructuring one- and two-value payloads, an ADT interpreter, Int patterns with `default`,
a switch as a statement, `_` bindings, a state machine, switches inside loops and beside
structs — and the answer to "what is in this `circle`?", which concept 11 could not ask.

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

The front-end half, and the only oracle the EXHAUSTIVENESS hole has: on the 15 programs of
`typecheck-corpus.txt` — five well-formed, ten `switch` must refuse, five of those for not
covering every case — `swiftc -typecheck` and `./lab.exe --typecheck` must reach the same
verdict. It needs no lowering, so it is the first half of this file to go green, and it stays
red until the sema hole is filled. A crash is not a rejection: exit 0 is accept, 1 is reject,
anything else is a crash. (`case .rect(let w)` binding a two-value payload as one stays out:
swiftc reads that as binding the whole tuple, a type our subset has no room for.)

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
