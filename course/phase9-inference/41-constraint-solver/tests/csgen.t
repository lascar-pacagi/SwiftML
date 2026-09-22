The system `csgen.ml` writes down, before anything is solved. This file needs no solver at
all — generation is given — and it is worth reading on its own, because every decision
concepts 05 and 07 made on the spot appears here as a fact nobody has acted on yet.

A literal is not an `Int`: it is a variable with a constraint saying which types it could
be. `is_int_literal`, turned from a tree walk into a fact.

  $ printf 'let n = 1\n' > lit.swift
  $ ./lab.exe --emit-constraints lit.swift
  $T0 : ExpressibleByIntegerLiteral

An operator is an OVERLOAD SET, so it generates a disjunction: exactly one alternative
holds, and which one cannot be read off the operands.

  $ printf 'let n = 1 + 2\n' > add.swift
  $ ./lab.exe --emit-constraints add.swift
  $T0 : ExpressibleByIntegerLiteral
  $T1 : ExpressibleByIntegerLiteral
  + is one of {(Int, Int) -> Int [$T2 == Int, $T0 == Int, $T1 == Int] | (Double, Double) -> Double [$T2 == Double, $T0 == Double, $T1 == Double] | (String, String) -> String [$T2 == String, $T0 == String, $T1 == String]}

Two functions may share a name. A call generates a disjunction over EVERY declaration it
could mean — `CSGen.cpp`'s `visitDeclRefExpr`, at small scale.

  $ cat > ovl.swift <<'EOF'
  > func f(_ x: Int) -> Int { return x }
  > func f(_ x: Double) -> Double { return x }
  > let a = f(1)
  > EOF
  $ ./lab.exe --emit-constraints ovl.swift
  Int == Int
  Double == Double
  $T0 : ExpressibleByIntegerLiteral
  f is one of {(Int) -> Int [$T1 == Int, $T0 == Int] | (Double) -> Double [$T1 == Double, $T0 == Double]}

The annotation is one more equality, in the same language as everything else. Nothing
gives it priority; it is a fact that happens to settle the rest.

  $ cat > annot.swift <<'EOF'
  > func g() -> Int { return 1 }
  > func g() -> Double { return 2.5 }
  > let d: Double = g()
  > EOF
  $ ./lab.exe --emit-constraints annot.swift
  $T0 : ExpressibleByIntegerLiteral
  $T0 == Int
  $T1 : ExpressibleByFloatLiteral
  $T1 == Double
  g is one of {() -> Int [$T2 == Int] | () -> Double [$T2 == Double]}
  $T2 == Double

A name with ONE declaration is not a choice, so no disjunction is generated for it.

  $ cat > one.swift <<'EOF'
  > func h(_ x: Int) -> Int { return x }
  > let a = h(1)
  > EOF
  $ ./lab.exe --emit-constraints one.swift
  Int == Int
  $T0 : ExpressibleByIntegerLiteral
  $T1 == Int
  $T0 == Int
