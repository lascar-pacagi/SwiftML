Actors: serialized isolation. An actor is a reference type whose methods must be reached with
`await` from outside (a hop onto its executor). RED until the TODO(39) hole (the isolation rule).

An actor runs and matches swiftc — its state is mutated through awaited calls:

  $ cat > a.swift <<'SWIFT'
  > actor Bank {
  >   var balance: Int
  >   init() { balance = 100 }
  >   func deposit(_ n: Int) { balance = balance + n }
  >   func withdraw(_ n: Int) -> Bool {
  >     if balance >= n { balance = balance - n; return true }
  >     return false
  >   }
  >   func report() -> Int { return balance }
  > }
  > let b = Bank()
  > await b.deposit(50)
  > let ok = await b.withdraw(30)
  > print(ok)
  > print(await b.report())
  > SWIFT
  $ ./lab.exe build a.swift -o a && ./a
  true
  120

Calling an actor method WITHOUT `await` from a nonisolated context is rejected, like swiftc:

  $ cat > bad.swift <<'SWIFT'
  > actor Counter {
  >   var value: Int
  >   init() { value = 0 }
  >   func get() -> Int { return value }
  > }
  > let c = Counter()
  > print(c.get())
  > SWIFT
  $ ./lab.exe --typecheck bad.swift
  7:7: error: call to actor-isolated instance method 'get' in a synchronous nonisolated context
  [1]

Inside the actor, access is synchronous (a method calling its own methods needs no await); and a
regular `class` is not isolated at all:

  $ cat > ok.swift <<'SWIFT'
  > actor A {
  >   var v: Int
  >   init() { v = 0 }
  >   func step() { v = v + 1 }
  >   func twice() { self.step()
  >     self.step() }
  >   func get() -> Int { return v }
  > }
  > class P { var x: Int
  >   init() { x = 9 }
  >   func get() -> Int { return x } }
  > let a = A()
  > await a.twice()
  > print(await a.get())
  > let p = P()
  > print(p.get())
  > SWIFT
  $ ./lab.exe build ok.swift -o ok && ./ok
  2
  9
