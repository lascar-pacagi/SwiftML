The two dynamic casts — `TODO(23a)`, the `Ast.Cast` arm of `gen_expr`, seen through `--emit-sil`
alone (running them also needs the IRGen holes; that is `run-existentials.t`). Type identity IS
witness-table identity here: `same_witness %e, $A` compares the container's table pointer with
`@wt.P.A`, one pointer compare, and both casts branch on it. `as?` produces an Optional across
the diamond — `.some(open)` on the proven side, `.none` on the other — and `as!` takes the
value or ends the block in `abort`.

`as?` is a diamond: one identity test, an `open_existential` on the branch that proved the
type, and the two `enum` tags that build the `A?`:

  $ cat > q.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > let p: P = A(x: 7)
  > if let a = p as? A { print(a.x) } else { print(-1) }
  > EOF
  $ ./lab.exe --emit-sil q.swift | grep 'same_witness\|open_existential\|enum #'
    %6 = same_witness %5, $A
    %8 = open_existential %5 : $A
    %9 = enum #1 (%8) $A?
    %11 = enum #0 () $A?

`as!` tests the same way but has no `.none` side: the failing block ends in `abort`, which is
the SIGABRT swiftc raises for a failed forced cast:

  $ cat > b.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > let p: P = A(x: 7)
  > let a = p as! A
  > print(a.x)
  > EOF
  $ ./lab.exe --emit-sil b.swift | grep 'same_witness\|open_existential\|abort'
    %6 = same_witness %5, $A
    %7 = open_existential %5 : $A
    abort "Could not cast value to 'A'"
  $ ./lab.exe --emit-sil b.swift | grep -c 'enum #' || true
  0

A cast to a type that does NOT conform has no table to compare against — `@wt.P.C` does not
exist, and naming it would be a LINK error — so the test is the constant `false`. The rest of
the diamond is built as usual (the open on the branch that can now never be taken is dead code,
and `-O` deletes it once the branch folds), but no `same_witness` is emitted:

  $ cat > unrel.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P {
  >   var x: Int
  >   func v() -> Int { return x }
  > }
  > struct C { var z: Int }
  > let p: P = A(x: 7)
  > if let c = p as? C { print(c.z) } else { print(-2) }
  > EOF
  $ ./lab.exe --emit-sil unrel.swift | grep -c 'same_witness' || true
  0
  $ ./lab.exe --emit-sil unrel.swift | grep -c 'open_existential' || true
  1
  $ ./lab.exe --emit-sil unrel.swift | grep 'integer_literal .Bool'
    %6 = integer_literal $Bool, false
  $ ./lab.exe --sil-opt unrel.swift | grep -c 'open_existential' || true
  0

Two casts in one program are two independent identity tests, one per target type — the slot
is the TABLE, so `as? A` and `as? B` compare against different globals:

  $ cat > two.swift <<'EOF'
  > protocol P { func v() -> Int }
  > struct A: P { func v() -> Int { return 1 } }
  > struct B: P { func v() -> Int { return 2 } }
  > let p: P = A()
  > if let a = p as? A { print(a.v()) } else { print(-1) }
  > if let b = p as? B { print(b.v()) } else { print(-2) }
  > EOF
  $ ./lab.exe --emit-sil two.swift | grep 'same_witness'
    %5 = same_witness %4, $A
    %27 = same_witness %26, $B

