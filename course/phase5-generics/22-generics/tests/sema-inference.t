Call-site INFERENCE — `TODO(22-sema)`, `infer_generic_call`, through `--typecheck`. A generic
function's type parameters are never written at the call: they are deduced from the arguments
sitting in `T` positions, checked against `T`'s constraint, and substituted into the return type
so a `-> T` call has a CONCRETE type at the caller. Wording is swiftc's.

One argument in a `T` position binds `T`, and the substituted result is usable concretely — the
`.x` on the result of `id` only typechecks because `T` came back as `A`:

  $ cat > ok.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > func id<T: P>(_ t: T) -> T { return t }
  > let a = id(A(x: 41))
  > print(a.x + 1)
  > print(id(A(x: 1)).v())
  > EOF
  $ ./lab.exe --typecheck ok.swift; echo "exit=$?"
  exit=0

Two arguments in the SAME `T` position must agree. Two `A`s are fine; an `A` and a `B` are
swiftc's "conflicting arguments", reported at the call:

  $ cat > conflict.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > func pair<T: P>(_ a: T, _ b: T) -> Int { return a.v() + b.v() }
  > print(pair(A(), A()))
  > print(pair(A(), B()))
  > EOF
  $ ./lab.exe --typecheck conflict.swift; echo "exit=$?"
  6:7: error: conflicting arguments to generic parameter 'T' ('A' vs. 'B')
  exit=1

An inferred binding must satisfy the constraint. `D` conforms to nothing, so it cannot be `T`:

  $ cat > constraint.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct D { var x: Int }
  > func one<T: P>(_ a: T) -> Int { return a.v() }
  > print(one(A()))
  > print(one(D(x: 1)))
  > EOF
  $ ./lab.exe --typecheck constraint.swift; echo "exit=$?"
  6:7: error: global function 'one' requires that 'D' conform to 'P'
  exit=1

A non-struct argument fails the same way — there is no conformance for `Int` here:

  $ cat > scalar.swift <<'EOF'
  > protocol P { func v() -> Int }
  > func one<T: P>(_ a: T) -> Int { return a.v() }
  > print(one(3))
  > EOF
  $ ./lab.exe --typecheck scalar.swift; echo "exit=$?"
  3:7: error: global function 'one' requires that 'Int' conform to 'P'
  exit=1

A parameter that is NOT in a `T` position is checked the ordinary way, so a `Bool` where an
`Int` is expected is still an error, and the `T` beside it still binds:

  $ cat > mixed.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > func scale<T: P>(_ a: T, _ k: Int) -> Int { return a.v() * k }
  > print(scale(A(), 7))
  > print(scale(A(), true))
  > EOF
  $ ./lab.exe --typecheck mixed.swift; echo "exit=$?"
  5:18: error: cannot convert value of type 'Bool' to specified type 'Int'
  exit=1

Arity is checked before anything is inferred. swiftc says `extra argument in call` here; we
keep the count-based sentence the rest of the compiler uses — same verdict, different sentence:

  $ cat > arity.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > func one<T: P>(_ a: T) -> Int { return a.v() }
  > print(one(A(), A()))
  > EOF
  $ ./lab.exe --typecheck arity.swift; echo "exit=$?"
  4:7: error: function 'one' expects 1 argument(s) but 2 given
  exit=1

A `where` clause is the same constraint spelled after the signature, and a generic calling a
generic binds `T` to the caller's own `T` — which already satisfies the constraint, so it is
accepted without ever becoming concrete:

  $ cat > where.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > func one<T: P>(_ t: T) -> Int { return t.v() }
  > func both<T>(_ a: T, _ b: T) -> Int where T: P { return one(a) + one(b) }
  > print(both(A(), A()))
  > EOF
  $ ./lab.exe --typecheck where.swift; echo "exit=$?"
  exit=0

The wrap of concept 21 still applies at a `T` position: a conformer passed to a plain `any P`
parameter is coerced. Passing an existential where `T` is expected is the one place we are
STRICTER than swiftc — Swift 5.7 opens the existential implicitly (SE-0352) and accepts it; we
have no way to recover the concrete type, so we refuse. §2 records the divergence:

  $ cat > mixwrap.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > func one<T: P>(_ t: T) -> Int { return t.v() }
  > func plain(_ p: P) -> Int { return p.v() }
  > let e: P = A()
  > print(plain(A()))
  > print(one(e))
  > EOF
  $ ./lab.exe --typecheck mixwrap.swift; echo "exit=$?"
  7:7: error: global function 'one' requires that 'any P' conform to 'P'
  exit=1
