# Phase 3 — Value types: structs, enums, pattern matching, optionals

Phase 2 gave `swiftml` a type system and SIL. Phase 3 gives it **Swift's data model** — the value
types that make Swift *Swift*: `struct` (product types with **value semantics**), `enum` (sum types
/ tagged unions, with associated values), `switch` (pattern matching with **exhaustiveness
checking**), and `Optional` — which turns out to be nothing but an enum plus sugar, the phase's
punchline.

```
struct  →  aggregates + copy-on-assign        (concept 10)
enum    →  { tag, payload } tagged unions      (concept 11)
switch  →  tag dispatch + payload binding      (concept 12)
T?      →  enum { none; some(T) } + sugar      (concept 13)
```

Every feature lands through **every stage** of the pipeline: lexer/parser (given, carry-forward),
sema (typing rules, exhaustiveness, the Equatable rule), SILGen (the lowering — your work), and
IRGen (LLVM aggregates: `insertvalue`/`extractvalue`/`getelementptr`).

## How Phase 3 relates to Phase 2

Same carry-forward contract as before: each concept is a self-contained library copied from the
previous one, the front end for new syntax is *given*, and your `TODO(NN)` holes are the genuinely
new machinery — almost always the **lowering** (how a language feature becomes SIL and LLVM).

| Concept | You implement | Checked against |
|---|---|---|
| `10-structs` | the value-type lowering: member read = `struct_extract`, write = `struct_element_addr`; IRGen aggregates | **value semantics** parity (`var q = p; q.x = 99` leaves `p` alone) |
| `11-enums-adts` | enum construction (`E.case(args)` → `Sil.Enum`) + IRGen tagged unions | `==` on payload-free enums, `rawValue`, Equatable rejection — all match swiftc |
| `12-pattern-matching` | the `switch` dispatch lowering (tag → `cond_br` chain → payload binding) + exhaustiveness | destructuring + a mini ADT interpreter run; exhaustiveness rejects like swiftc |
| `13-optionals` | the optional lowering (implicit `T`→`T?` wrap, `!` trap, `??`, `if let`) over the enum engine | force-unwrap-nil **traps with swiftc's exact exit code (133)** |

**Milestone M3:** value types end-to-end — struct/enum/switch/optional programs compile, run, and
match `swiftc` byte-for-byte, including trap behavior. (`14-memory-layout` is deferred; the phase
pivoted straight into the optimizer.)
