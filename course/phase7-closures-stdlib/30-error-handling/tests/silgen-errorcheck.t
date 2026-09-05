TODO(30a) — the post-call error check, in `silgen.ml`. An error is a value in one register, so
propagation is a BRANCH: after any call that can throw, test the register and take the error
edge or carry on. Every case here avoids `do`/`catch`, so it reads 30a alone — `try?` and
`try!` install their own handlers, and a throw that leaves the function propagates.

`try?` turns the error edge into `nil`, `try!` into a trap. Both are the same branch with a
different destination:

  $ cat > q.swift <<'SWIFT'
  > enum E: Error { case x }
  > func f(_ n: Int) throws -> Int {
  >   if n == 0 { throw E.x }
  >   return n * 2
  > }
  > print((try? f(0)) ?? 0 - 7)
  > print((try? f(21)) ?? 0 - 7)
  > print(try! f(21))
  > SWIFT
  $ ./lab.exe build q.swift -o q && ./q
  -7
  42
  42

  $ ./lab.exe build q.swift -O -o qO && ./qO
  -7
  42
  42

The check is two runtime calls and a `cond_br` — no new SIL instruction was needed for any of
this, which is the whole point of putting the error in a register:

  $ ./lab.exe --emit-sil q.swift | grep -c 'rt.error_get' || true
  3

`try!` on a thrown error traps with swiftc's exit code:

  $ printf 'enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nprint(try! f())\n' > t.swift
  $ ./lab.exe build t.swift -o tt
  $ sh -c './tt; echo "exit=$?"' 2>/dev/null
  exit=133

Propagation is the same branch repeated: each level returns early, the register still set, and
the outermost `try?` reads it. Three levels deep, no unwinding anywhere:

  $ cat > p.swift <<'SWIFT'
  > enum E: Error { case x }
  > func lvl3() throws -> Int { throw E.x }
  > func lvl2() throws -> Int { return try lvl3() }
  > func lvl1() throws -> Int { return try lvl2() }
  > print((try? lvl1()) ?? 0 - 3)
  > SWIFT
  $ ./lab.exe build p.swift -o p && ./p
  -3

The error edge is an EXIT, so it runs the cleanups it crosses: the defers of every scope
between the throwing call and the handler, newest first. This is what `goto_handler` is for,
and what the `HJump` handler's scope depth records.

  $ cat > d.swift <<'SWIFT'
  > enum E: Error { case x }
  > func f(_ n: Int) throws -> Int {
  >   defer { print(1) }
  >   defer { print(2) }
  >   if n == 0 { throw E.x }
  >   return n
  > }
  > print((try? f(7)) ?? 0 - 1)
  > print((try? f(0)) ?? 0 - 9)
  > SWIFT
  $ ./lab.exe build d.swift -o d && ./d
  2
  1
  7
  2
  1
  -9
