The answers, through `--emit-tast`: every node with the type it was given, and every
overloaded name resolved to the declaration chosen — `f#1` is the second `f` in source order.
Goes green with TODO(41a-d).

`1 + 2` is Int arithmetic. Double satisfies every constraint too — the SCORE rules it out,
one point for each literal that had to leave its default type.

  $ printf 'let n = 1 + 2\n' > s1.swift
  $ ./lab.exe --emit-tast s1.swift
  (let n (+ (int_lit 1 : Int) (int_lit 2 : Int) : Int))

One Double operand and the literal follows it, recorded ON the literal's node, exactly as
`swiftc -dump-ast` shows.

  $ printf 'let d = 1 + 2.0\n' > s2.swift
  $ ./lab.exe --emit-tast s2.swift
  (let d (+ (int_lit 1 : Double) (double_lit 2 : Double) : Double))

THE case a bidirectional checker cannot do: both calls are written `g()`, and the only
thing that tells them apart is the type each context wants back.

  $ cat > s3.swift <<'EOF'
  > func g() -> Int { return 1 }
  > func g() -> Double { return 2.5 }
  > let c: Double = g()
  > let d: Int = g()
  > EOF
  $ ./lab.exe --emit-tast s3.swift
  (func g () -> Int {(return (int_lit 1 : Int))})
  (func g () -> Double {(return (double_lit 2.5 : Double))})
  (let c (g#1  : Double))
  (let d (g#0  : Int))

An argument settles it as well as a result, and takes the literal with it.

  $ cat > s4.swift <<'EOF'
  > func f(_ x: Int) -> Int { return x }
  > func f(_ x: Double) -> Double { return x }
  > let a = f(1)
  > let b: Double = f(1)
  > EOF
  $ ./lab.exe --emit-tast s4.swift
  (func f (x:Int) -> Int {(return (local x : Int))})
  (func f (x:Double) -> Double {(return (local x : Double))})
  (let a (f#0 (int_lit 1 : Int) : Int))
  (let b (f#1 (int_lit 1 : Double) : Double))

Overloads may differ in ARITY too; the ones that cannot fit are dropped before the
disjunction is built, so the search never considers them.

  $ cat > s5.swift <<'EOF'
  > func k(_ x: Int) -> Int { return x }
  > func k(_ x: Int, _ y: Int) -> Int { return x + y }
  > let a = k(1)
  > let b = k(1, 2)
  > EOF
  $ ./lab.exe --emit-tast s5.swift
  (func k (x:Int) -> Int {(return (local x : Int))})
  (func k (x:Int y:Int) -> Int {(return (+ (local x : Int) (local y : Int) : Int))})
  (let a (k#0 (int_lit 1 : Int) : Int))
  (let b (k#1 (int_lit 1 : Int) (int_lit 2 : Int) : Int))

`+` on Strings, chosen from the same disjunction as the arithmetic ones.

  $ printf 'let s = "a" + "b"\n' > s6.swift
  $ ./lab.exe --emit-tast s6.swift
  (let s (+ (string_lit "a" : String) (string_lit "b" : String) : String))
