The sema hole, TODO(12-sema): a `switch` over an enum with no `default` must cover EVERY case.
Every program here is one swiftc refuses and the skeleton accepts, so this file is red until you
add the check; the rules that are already given live in `sema-switch.t`. `--typecheck` stops
after sema, so no lowering is involved.

One case of a two-case enum, no `default`: `switch must be exhaustive`, swiftc's own words:

  $ cat > one.swift <<'EOF'
  > enum E { case a, b }
  > let e = E.a
  > switch e {
  > case .a: print(1)
  > }
  > EOF
  $ ./lab.exe --typecheck one.swift
  3:1: error: switch must be exhaustive
  [1]

Two of three is still not all three — the missing case is `dot`:

  $ cat > two.swift <<'EOF'
  > enum Shape {
  >   case circle(Int)
  >   case rect(Int, Int)
  >   case dot
  > }
  > let s = Shape.dot
  > switch s {
  > case .circle(let r): print(r)
  > case .rect(let w, let h): print(w + h)
  > }
  > EOF
  $ ./lab.exe --typecheck two.swift
  7:1: error: switch must be exhaustive
  [1]

Listing the SAME case twice covers one case, not two:

  $ cat > dup.swift <<'EOF'
  > enum E { case a, b }
  > let e = E.a
  > switch e {
  > case .a: print(1)
  > case .a: print(2)
  > }
  > EOF
  $ ./lab.exe --typecheck dup.swift
  3:1: error: switch must be exhaustive
  [1]

An empty switch over a non-empty enum covers nothing:

  $ cat > empty.swift <<'EOF'
  > enum E { case a, b }
  > let e = E.a
  > switch e {
  > }
  > EOF
  $ ./lab.exe --typecheck empty.swift
  3:1: error: switch must be exhaustive
  [1]

The check runs inside a function body too, on a switch that is the function's only statement:

  $ cat > infn.swift <<'EOF'
  > enum E { case a, b, c }
  > func f(_ e: E) -> Int {
  >   switch e {
  >   case .a: return 1
  >   case .b: return 2
  >   }
  > }
  > print(f(E.a))
  > EOF
  $ ./lab.exe --typecheck infn.swift
  3:3: error: switch must be exhaustive
  [1]
