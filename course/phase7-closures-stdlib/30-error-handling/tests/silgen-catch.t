TODO(30b) — the catch dispatch, in `silgen.ml`. `do`/`catch` is a switch on the error ordinal:
each clause with a pattern compares, a bare clause matches anything, and an unmatched error
keeps travelling. A bare `throw` inside the `do` reaches the dispatch without going through
the post-call check, so these cases read 30b on its own.

A pattern clause selects by case; the clauses are tried in source order:

  $ cat > a.swift <<'SWIFT'
  > enum E: Error { case a, b, c }
  > do { throw E.b }
  > catch E.a { print(1) }
  > catch E.b { print(2) }
  > catch E.c { print(3) }
  > SWIFT
  $ ./lab.exe build a.swift -o a && ./a
  2

A bare clause matches anything, and it is the LAST one for a reason — anything after it is
unreachable:

  $ cat > b.swift <<'SWIFT'
  > enum E: Error { case a, b }
  > do { throw E.b }
  > catch E.a { print(1) }
  > catch { print(99) }
  > SWIFT
  $ ./lab.exe build b.swift -o b && ./b
  99

A `do` whose body does not throw runs to the end and skips the dispatch entirely:

  $ cat > c.swift <<'SWIFT'
  > enum E: Error { case a }
  > do { print(7) }
  > catch { print(0 - 1) }
  > print(8)
  > SWIFT
  $ ./lab.exe build c.swift -o c && ./c
  7
  8

An error no clause matches keeps travelling — out of the `do`, and out of the function:

  $ cat > r.swift <<'SWIFT'
  > enum E: Error { case a, b }
  > func inner(_ n: Int) throws -> Int {
  >   if n == 1 { throw E.a }
  >   return n
  > }
  > func outer(_ n: Int) throws -> Int {
  >   do { return try inner(n) } catch E.b { return 0 - 5 }
  > }
  > do { print(try outer(1)) } catch E.a { print(42) }
  > do { print(try outer(4)) } catch { print(0 - 1) }
  > SWIFT
  $ ./lab.exe build r.swift -o r && ./r
  42
  4

Matching a clause CLEARS the error — otherwise the next throwing call would see a stale one:

  $ cat > s.swift <<'SWIFT'
  > enum E: Error { case a }
  > func f(_ n: Int) throws -> Int {
  >   if n == 0 { throw E.a }
  >   return n
  > }
  > do { print(try f(0)) } catch { print(0 - 1) }
  > do { print(try f(5)) } catch { print(0 - 2) }
  > SWIFT
  $ ./lab.exe build s.swift -o s && ./s
  -1
  5

A defer declared INSIDE the `do` body fires before the catch body — the error edge leaves that
scope, and leaving a scope runs its defers. It used to jump straight to the dispatch and print
`3` alone where swiftc prints `2` then `3`.

  $ cat > df.swift <<'SWIFT'
  > enum E: Error { case x }
  > func mayThrow() throws -> Int { throw E.x }
  > func run() {
  >   do {
  >     defer { print(2) }
  >     let v = try mayThrow()
  >     print(v)
  >   } catch {
  >     print(3)
  >   }
  > }
  > run()
  > SWIFT
  $ ./lab.exe build df.swift -o df && ./df
  2
  3

  $ ./lab.exe build df.swift -O -o dfO && ./dfO
  2
  3
