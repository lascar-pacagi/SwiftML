TODO(39) — the isolation rule, which is the whole concept. Three conditions have to hold before
the call is an error, and each of the three has a case here that would go green if you dropped it.

Condition 1 — the receiver's type is an ACTOR. A synchronous call to an actor's method from the
top level is rejected, in swiftc's words (`diag::actor_isolated_call_decl`,
`DiagnosticsSema.def:5960`), at the call's own column.

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
  7:7: error: call to actor-isolated instance method 'get()' in a synchronous nonisolated context
  [1]
  $ swiftc -typecheck bad.swift 2>&1 | head -1
  bad.swift:7:9: error: call to actor-isolated instance method 'get()' in a synchronous nonisolated context [#ActorIsolatedCall]

Drop condition 1 and a plain `class` starts failing too. It must not: a class has no isolation,
and every class program from concept 25 onwards still type-checks.

  $ cat > cls.swift <<'SWIFT'
  > class P {
  >   var x: Int
  >   init() { x = 5 }
  >   func get() -> Int { return x }
  > }
  > let p = P()
  > print(p.get())
  > SWIFT
  $ ./lab.exe --typecheck cls.swift && echo accepted
  accepted

Condition 2 — the call is not under `await`. The same program with `await` is accepted: the
`await` is the hop onto the actor's executor, which is what serializes the access.

  $ cat > good.swift <<'SWIFT'
  > actor Counter {
  >   var value: Int
  >   init() { value = 0 }
  >   func get() -> Int { return value }
  > }
  > let c = Counter()
  > print(await c.get())
  > SWIFT
  $ ./lab.exe --typecheck good.swift && echo accepted
  accepted

The flag tracks the OPERAND of an `await`, not the statement: a second, un-awaited call in the
same statement is still rejected, and an un-awaited call in the next statement is too.

  $ cat > mixed.swift <<'SWIFT'
  > actor Counter {
  >   var value: Int
  >   init() { value = 0 }
  >   func get() -> Int { return value }
  > }
  > let c = Counter()
  > let a = await c.get()
  > let b = c.get()
  > print(a + b)
  > SWIFT
  $ ./lab.exe --typecheck mixed.swift
  8:9: error: call to actor-isolated instance method 'get()' in a synchronous nonisolated context
  [1]

Condition 3 — we are outside the actor. Inside its own methods an actor is already on its
executor, so `self.step()` is a direct, synchronous call and must stay one.

  $ cat > inside.swift <<'SWIFT'
  > actor A {
  >   var v: Int
  >   init() { v = 0 }
  >   func step() { v = v + 1 }
  >   func twice() { self.step()
  >     self.step() }
  >   func get() -> Int { return v }
  > }
  > let a = A()
  > await a.twice()
  > print(await a.get())
  > SWIFT
  $ ./lab.exe --typecheck inside.swift && echo accepted
  accepted
  $ ./lab.exe build inside.swift -o inside && ./inside
  2

A nonisolated FUNCTION is outside the actor as much as the top level is, so a synchronous call
in an ordinary `func` is rejected too.

  $ cat > infn.swift <<'SWIFT'
  > actor Counter {
  >   var value: Int
  >   init() { value = 0 }
  >   func get() -> Int { return value }
  > }
  > func peek(_ c: Counter) -> Int { return c.get() }
  > let c = Counter()
  > print(peek(c))
  > SWIFT
  $ ./lab.exe --typecheck infn.swift
  6:41: error: call to actor-isolated instance method 'get()' in a synchronous nonisolated context
  [1]

DOCUMENTED v0 DIVERGENCE: our third condition is per-TYPE, not per-INSTANCE. A method of `A`
calling ANOTHER `A` instance synchronously is accepted here; swiftc rejects it, because isolation
in Swift belongs to the instance and `other` may be on a different executor. Its wording differs
too — "a synchronous actor-isolated context", since the caller is itself isolated.

  $ cat > peer.swift <<'SWIFT'
  > actor A {
  >   var v: Int
  >   init() { v = 0 }
  >   func step() { v = v + 1 }
  >   func poke(_ other: A) { other.step() }
  > }
  > let a = A()
  > print(0)
  > SWIFT
  $ ./lab.exe --typecheck peer.swift && echo "we accept it (v0)"
  we accept it (v0)
  $ swiftc -typecheck peer.swift 2>&1 | head -1
  peer.swift:5:33: error: call to actor-isolated instance method 'step()' in a synchronous actor-isolated context [#ActorIsolatedCall]
