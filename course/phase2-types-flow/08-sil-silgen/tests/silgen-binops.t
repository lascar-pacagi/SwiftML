TODO(08c) — the ordinary binary operator, through `--emit-sil`. `&&` and `||` are not here: they
short-circuit, so the given `gen_expr` lowers them as a branch diamond and `silgen-if.t` is where
that shape is checked. Everything else is one `binop` instruction, and the interest is in the two
types it carries — the type the operation happens AT, and the type of its result.

Nothing in this file branches, so it reports on TODO(08c) alone: it can go green with the memory
model and every control-flow hole still raising.

Arithmetic on `Int` produces an `Int`, and precedence is already settled by the parser — the SIL
just shows the multiply happening before the add:

  $ printf 'print(2 + 3 * 4)\n' > a1.swift
  $ ./lab.exe --emit-sil a1.swift | grep binop
    %3 = binop "*" %1, %2 $Int
    %4 = binop "+" %0, %3 $Int

Arithmetic on `Double` is the same instruction carrying a different type:

  $ printf 'print(1.5 * 2.0)\n' > a2.swift
  $ ./lab.exe --emit-sil a2.swift | grep binop
    %2 = binop "*" %0, %1 $Double

A comparison is where the two types come apart: it compares `Int`s and produces a `$Bool`, which
is what `result_ty` is for:

  $ printf 'print(3 < 4)\n' > a3.swift
  $ ./lab.exe --emit-sil a3.swift | grep binop
    %2 = binop "<" %0, %1 $Bool

Remainder is an operator like any other here — no special case:

  $ printf 'print(7 %% 2)\n' > a4.swift
  $ ./lab.exe --emit-sil a4.swift | grep binop
    %2 = binop "%" %0, %1 $Int

An `Int` literal beside a `Double` makes the whole operation `Double`: sema already decided that,
and the lowering has to agree, or IRGen emits an `Int` multiply on a `double` and clang rejects
the module:

  $ printf 'print(2.5 + 1)\n' > a5.swift
  $ ./lab.exe --emit-sil a5.swift | grep binop
    %2 = binop "+" %0, %1 $Double
