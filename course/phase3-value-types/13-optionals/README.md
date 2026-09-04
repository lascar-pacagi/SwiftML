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
> Optional chaining (`a?.b`), implicitly-unwrapped `T!`, and `guard let` are exercises. Two rules
> are stricter than swiftc and stay out of the oracle: `print` of an optional (swiftc prints
> `Optional(5)`) and `a == b` between two optionals (swiftc synthesizes it from `Equatable`) — the
> explainer's diagnostics table lists the honest set.

## Done when

`make lab C=phase3-value-types/13-optionals` is green: one cram file per hole (`silgen-wrap.t`,
`silgen-force-unwrap.t`, `silgen-coalesce.t`, `silgen-iflet.t`, each `TODO` until you start it)
beside the given `sema-optionals.t` and the end-to-end `run-optionals.t`, the alcotest's five
groups, and `oracle.t` — 15 programs compiled by `swiftc` and by `./lab.exe build`, run, and
compared byte for byte; the force-unwrap trap's **exit 133** and message checked against swiftc's
own; and 16 more where `swiftc -typecheck` and `--typecheck` must reach the same verdict.
