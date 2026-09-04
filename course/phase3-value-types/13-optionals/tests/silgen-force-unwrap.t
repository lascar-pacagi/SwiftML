The second silgen hole, TODO(13): `e!`. It tests the tag, extracts the payload on `.some`, and
on `.none` ends the block in `Sil.Trap` — the message and the exit code are swiftc's, and
`run-optionals.t` checks them by running. `--emit-sil` stops after SILGen. It needs the wrap
hole (an `Int?` has to be built before it can be unwrapped) but neither `??` nor `if let`.

`a!` on a `let a: Int? = 5`: a tag test, the payload on the taken side, and a `trap` carrying
Swift's own sentence on the other:

  $ cat > bang.swift <<'EOF'
  > let a: Int? = 5
  > print(a!)
  > EOF
  $ ./lab.exe --emit-sil bang.swift
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 5
    %1 = enum #1 (%0) $Int?
    %2 = alloc_stack $Int?  // a
    store %1 to %2
    %4 = load %2 $Int?
    %5 = enum_tag %4
    %6 = integer_literal $Int, 1
    %7 = binop "==" %5, %6 $Bool
    cond_br %7, bb1, bb2
  bb1:
    %8 = enum_payload %4, #0 $Int
    %9 = apply @print(%8)
    return
  bb2:
    trap "Fatal error: Unexpectedly found nil while unwrapping an Optional value"
  }

The trap block is a TERMINATOR, not a call — nothing after it runs, and the statement that
follows the unwrap is generated in the block the tag test fell into:

  $ cat > after.swift <<'EOF'
  > let a: Int? = 5
  > print(a!)
  > print(7)
  > EOF
  $ ./lab.exe --emit-sil after.swift | grep -E '^bb|trap|apply'
  bb0:
  bb1:
    %9 = apply @print(%8)
    %11 = apply @print(%10)
  bb2:
    trap "Fatal error: Unexpectedly found nil while unwrapping an Optional value"

`f(3)!` unwraps a CALL result — any optional expression will do, not just a variable:

  $ cat > call.swift <<'EOF'
  > func f(_ n: Int) -> Int? {
  >   if n < 0 { return nil }
  >   return n * 2
  > }
  > print(f(3)!)
  > EOF
  $ ./lab.exe --emit-sil call.swift | sed -n '/sil @main/,/^}/p'
  sil @main() -> $() {
  bb0:
    %0 = integer_literal $Int, 3
    %1 = function_ref @f
    %2 = apply %1(%0)
    %3 = enum_tag %2
    %4 = integer_literal $Int, 1
    %5 = binop "==" %3, %4 $Bool
    cond_br %5, bb1, bb2
  bb1:
    %6 = enum_payload %2, #0 $Int
    %7 = apply @print(%6)
    return
  bb2:
    trap "Fatal error: Unexpectedly found nil while unwrapping an Optional value"
  }

Two unwraps are two independent tests — each `!` gets its own tag check and its own trap:

  $ cat > twice.swift <<'EOF'
  > let a: Int? = 5
  > let b: Int? = 6
  > print(a! + b!)
  > EOF
  $ ./lab.exe --emit-sil twice.swift | grep -cE 'trap '
  2

Unwrapping a `nil` the compiler can see is still a runtime trap, not an error — Swift checks
this at run time, and so do we:

  $ cat > isnil.swift <<'EOF'
  > let a: Int? = nil
  > print(a!)
  > EOF
  $ ./lab.exe --emit-sil isnil.swift | grep -E 'enum #|trap '
    %0 = enum #0 () $Int?
    trap "Fatal error: Unexpectedly found nil while unwrapping an Optional value"
