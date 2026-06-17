Error handling: throws/try/do-catch/try?/try!/defer, all PURE DESUGARING over @swiftml.error.
RED until the TODO(30) holes (the post-call error check + the do-catch dispatch).

do-catch selects by error case; nested propagation; try?/try! all match swiftc:

  $ cat > a.swift <<'SWIFT'
  > enum MathError: Error { case divByZero, negative }
  > func safeDiv(_ a: Int, _ b: Int) throws -> Int {
  >   if b == 0 { throw MathError.divByZero }
  >   return a / b
  > }
  > do {
  >   print(try safeDiv(10, 2))
  >   print(try safeDiv(1, 0))
  >   print(999)
  > } catch MathError.divByZero {
  >   print(-1)
  > } catch {
  >   print(-2)
  > }
  > print(try! safeDiv(9, 3))
  > print((try? safeDiv(5, 0)) ?? -7)
  > print((try? safeDiv(8, 4)) ?? -7)
  > SWIFT
  $ ./lab.exe build a.swift -o a && ./a
  5
  -1
  3
  -7
  2
  $ ./lab.exe build a.swift -O -o aO && ./aO
  5
  -1
  3
  -7
  2

The SIL shows the desugaring — no new instructions, just the error-register calls + branches:

  $ ./lab.exe --emit-sil a.swift | grep -c 'rt.error_get'
  6
  $ ./lab.exe --emit-sil a.swift | grep -c 'rt.error_set'
  5

defer fires LIFO on every exit, including the throw path:

  $ cat > d.swift <<'SWIFT'
  > enum E: Error { case x }
  > func f(_ n: Int) throws -> Int {
  >   defer { print(1) }
  >   defer { print(2) }
  >   if n == 0 { throw E.x }
  >   return n
  > }
  > do { print(try f(7)) } catch { print(-1) }
  > do { print(try f(0)) } catch { print(-9) }
  > SWIFT
  $ ./lab.exe build d.swift -o d && ./d
  2
  1
  7
  2
  1
  -9

try! on a thrown error traps with swiftc's exit code (133):

  $ printf 'enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nprint(try! f())\n' > t.swift
  $ ./lab.exe build t.swift -o tt
  $ sh -c './tt; echo "exit=$?"' 2>/dev/null
  exit=133

The diagnostics match swiftc:

  $ printf 'enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nfunc g() -> Int { return f() }\n' > m.swift
  $ ./lab.exe --typecheck m.swift 2>&1 | head -1
  3:26: error: call can throw, but it is not marked with 'try' and the error is not handled

  $ printf 'enum E: Error { case x }\nfunc f() throws -> Int { throw E.x }\nfunc g() -> Int { return try f() }\n' > u.swift
  $ ./lab.exe --typecheck u.swift 2>&1 | head -1
  3:30: error: errors thrown from here are not handled
