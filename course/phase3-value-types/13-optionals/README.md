# 13 · Optionals (`T?` = an enum)

**Objective:** add `Optional` — `T?`, `nil`, `!`, `if let`, `??` — and discover that it's **not a new
mechanism at all**: `Optional<T>` is literally `enum { case none; case some(T) }`, so all the sugar
desugars to the enum + pattern-matching engine you built in concepts 11–12. The one genuinely new
thing is the **force-unwrap trap** on `nil`, which we match to swiftc exactly (message + exit 133).

**Prerequisites:** the switch compiler (concepts 11–12), given and working — its `Enum`/`Enum_tag`/
`Enum_payload` instructions are exactly what optionals reuse.

**You edit (the optional *lowering*, all in `silgen.ml`):**

- `TODO(13)`: `gen_expr_as` (the **wrap**: `nil` → `.none`, a `T` → `.some(T)`), `Force_unwrap` (`e!`
  → tag-check + `Trap` on nil + payload), `Coalesce` (`a ?? b`), and `If_let` (`if let` → some-check +
  bind). Each is a small CFG on top of `Enum`/`Enum_tag`/`Enum_payload`.

Given: the contracts (`Types.TOptional`, `Nil`/`Force_unwrap`/`Coalesce`/`If_let` AST, the SIL `Trap`
terminator), the lexer (`?`/`!`/`nil`), the parser (`T?`, `e!`, `??`, `if let`), all the sema (`nil`
contextual typing, implicit wrapping, the unwrap/coalesce rules), and IRGen (`Trap` → `@llvm.trap`,
`T?` → `{ i64, T }`).

**Design oracle:** the Swift stdlib's `Optional` enum; `swift/lib/IRGen/GenEnum.cpp` (spare-bit
layout, why `Optional<ptr>` is pointer-sized); the Swift runtime's force-unwrap trap.

## What this concept adds

- `T?` types, the `nil` literal, **implicit wrapping** (`let x: Int? = 5` ⇒ `.some(5)`), force-unwrap
  `e!`, optional binding `if let x = opt { … } else { … }`, nil-coalescing `a ?? b`, and `== nil`.
- Lowering: `T?` is `{ i64 tag, T }` (`none` = tag 0, `some` = tag 1), reusing the enum instructions.
- The **force-unwrap trap**: a `Sil.Trap` terminator → `@llvm.trap` (SIGTRAP → exit **133**), with the
  same "Fatal error: Unexpectedly found nil…" message as swiftc.

> **Scope (v0).** `Int?`/`Bool?`/struct?/etc. (monomorphized — we have no generics until Phase 6).
> Optional chaining (`a?.b`), implicitly-unwrapped `T!`, and `guard let` are exercises.

## Done when

`make lab C=phase3-value-types/13-optionals` is green: the cram test **builds and runs** optional
programs — `if let`/`??`/`!`/`== nil` — **and the force-unwrap trap matches swiftc's exit code (133)**;
the alcotest pins the sema rules and the `{ tag, payload }`/trap IR. Output matches `swiftc`.
