TODO(40b) — the statement macro. `#assert(cond)` is not sugar over a call: it expands to the `if`
a hand-written assertion would be, `if cond { } else { fatalError() }`, and `fatalError()` is the
given primitive SILGen turns into a trap.

NOTE this one is OURS. Swift has no `#assert` macro — it has the ordinary function `assert(_:)` —
so swiftc cannot arbitrate the spelling. What it can arbitrate is the BEHAVIOUR, and the cases
below run `swiftc`'s `assert` beside our `#assert` on the same condition.

A true assertion is silent and the program carries on.

  $ cat > ok.swift <<'SWIFT'
  > let x = 5
  > #assert(x > 0)
  > #assert(x == 5)
  > print(99)
  > SWIFT
  $ ./lab.exe build ok.swift -o ok && ./ok
  99
  $ printf 'let x = 5\nassert(x > 0)\nassert(x == 5)\nprint(99)\n' > ok_sw.swift
  $ swiftc -Onone ok_sw.swift -o ok_sw && ./ok_sw
  99

A false assertion traps: SIGTRAP, exit 133 — the same exit code `swiftc`'s failed `assert`
produces, and the same one concept 13's force-unwrap of `nil` produces.

  $ cat > bad.swift <<'SWIFT'
  > let x = 5
  > #assert(x > 10)
  > print(99)
  > SWIFT
  $ ./lab.exe build bad.swift -o bad
  $ sh -c './bad; echo exit=$?' 2>/dev/null
  exit=133
  $ printf 'let x = 5\nassert(x > 10)\nprint(99)\n' > bad_sw.swift
  $ swiftc -Onone bad_sw.swift -o bad_sw
  $ sh -c './bad_sw; echo exit=$?' 2>/dev/null
  exit=133

Both compilers lose the buffered `print` before the trap, so the two agree on stdout as well as
on the exit code — worth knowing, because it is why the case above prints nothing at all.

`--emit-ast` shows the program as the PARSER saw it, so `#assert` is still a macro there — the
expander runs after that dump and before sema. What it becomes (an `if` whose else-branch calls
`fatalError`) is checked on the tree itself by `test_macros.ml`; here it is checked by what the
program does.

  $ ./lab.exe --emit-ast bad.swift
  (let x 5)
  (macro #assert (> x 10))
  (print 99)

That it really is an `if`, and not a call that always evaluates its argument, shows in a
condition with a side effect: the assertion's operand is evaluated once, and the branch not
taken runs nothing.

  $ cat > side.swift <<'SWIFT'
  > func loud(_ n: Int) -> Bool {
  >   print(n)
  >   return n > 0
  > }
  > #assert(loud(1))
  > print(99)
  > SWIFT
  $ ./lab.exe build side.swift -o side && ./side
  1
  99

Being a statement expansion, it composes with ordinary control flow — inside a function, inside
a loop — and only the failing one traps.

  $ cat > infn.swift <<'SWIFT'
  > func check(_ n: Int) -> Int {
  >   #assert(n >= 0)
  >   return n * 2
  > }
  > print(check(3))
  > var t = 0
  > for i in 0 ..< 3 {
  >   #assert(i < 3)
  >   t = t + i
  > }
  > print(t)
  > print(check(-1))
  > SWIFT
  $ ./lab.exe build infn.swift -o infn
  $ sh -c './infn; echo exit=$?' 2>/dev/null
  exit=133

The same program with the failing call removed runs to the end.

  $ cat > infn2.swift <<'SWIFT'
  > func check(_ n: Int) -> Int {
  >   #assert(n >= 0)
  >   return n * 2
  > }
  > print(check(3))
  > var t = 0
  > for i in 0 ..< 3 {
  >   #assert(i < 3)
  >   t = t + i
  > }
  > print(t)
  > SWIFT
  $ ./lab.exe build infn2.swift -o infn2 && ./infn2
  6
  3
