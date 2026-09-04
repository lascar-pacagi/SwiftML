THE HEADLINE TEST: this file asks swiftc on every run, so the numbers a human wrote down in
the other files can never drift from what Swift actually prints. `make oracle F=…` does the
same for one file. A program either compiler refuses is reported as such, never counted as
agreement; when our refusal comes from an unfinished hole the loop stops there, so the file
reads as not-started rather than as a wall of diffs.

The 15 programs of `oracle-corpus.txt` are built by `swiftc -Onone` AND by `./lab.exe build`,
both binaries are run, and stdout + exit code must be identical. They are the whole optional
story: `if let`, `??`, `!`, `== nil`, `-> Int?` functions wrapping bare values at `return`,
optionals reassigned through a `var`, optional struct fields under value-semantics copies,
optionals as arguments, and optionals accumulated in loops.

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

Force-unwrapping `nil` must FAIL the way swiftc's does: the same sentence on stderr and the
same exit code, 133 (128 + SIGTRAP). It gets its own check because the two messages are not
byte-identical — swiftc prefixes the source location, `p.swift:2: Fatal error: …`, and we print
the sentence alone — so the comparison strips everything before `Fatal error`. The `sh -c`
wrappers keep the shell's nondeterministic "Trace/BPT trap: <pid>" job message out of the
transcript.

  $ printf 'let x: Int? = nil\nprint(x!)\n' > trap.swift
  $ swiftc -Onone trap.swift -o swtrap >/dev/null 2>&1
  $ ./lab.exe build trap.swift -o mltrap >/dev/null 2>&1
  $ sh -c './swtrap 2>sw.err; echo "swiftc exit=$?"' 2>/dev/null
  swiftc exit=133
  $ sh -c './mltrap 2>ml.err; echo "ours exit=$?"' 2>/dev/null
  ours exit=133
  $ sed 's/^.*Fatal error/Fatal error/' sw.err
  Fatal error: Unexpectedly found nil while unwrapping an Optional value
  $ sed 's/^.*Fatal error/Fatal error/' ml.err
  Fatal error: Unexpectedly found nil while unwrapping an Optional value

The front-end half: on the 16 programs of `typecheck-corpus.txt` — six well-formed, ten the
optional rules must refuse — `swiftc -typecheck` and `./lab.exe --typecheck` must reach the same
verdict. Running programs can only exercise what we accept; this half pins what we refuse, and
it needs no lowering, so it is green from the skeleton. A crash is not a rejection: exit 0 is
accept, 1 is reject, anything else is a crash. (`print(opt)` stays out: swiftc prints
`Optional(5)`, we refuse — the divergence of §2.)

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
