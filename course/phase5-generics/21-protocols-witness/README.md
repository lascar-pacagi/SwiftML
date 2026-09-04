# 21 · Protocols & witness tables

**Objective:** Swift's `protocol` — through every stage. Declare method requirements; conform
structs to them (with **methods**, new here); use a protocol as a **type** (`any P`, the
existential); and make `p.area()` on an existential work by **dynamic dispatch through a witness
table** — a per-(type, protocol) array of function pointers, exactly swiftc's design. Phase 5
opens here: generics (22), existential containers (23), and specialization (24) all build on this
table.

**Prerequisites:** the Phase-4 compiler (this concept carries it forward, including `-O`).

**You edit:**
- `sema.ml` — `TODO(21-sema)`: the **conformance check** (`struct_conforms`: every requirement
  implemented with the exact signature) — it powers both the error and the implicit coercion.
- `silgen.ml` — `TODO(21a/b/c)`: the **existential wrap** (`init_existential`), **method
  dispatch** (static `Apply` on concrete receivers vs `Apply_witness` through the table), and
  **witness-table construction** (one per conformance, impls in requirement order).

**Design oracle:** `../../../swift/lib/AST/ProtocolConformance.cpp`, `swift/lib/SILGen/SILGenPoly.cpp`
(witness thunks), and `swift/lib/IRGen/GenProto.cpp` (witness tables in IR).

## What this concept adds

- **Methods on structs** (given): `func` inside a struct, `self`, implicit field/method access;
  lowered as plain functions `S.m` with `self` as argument 0 — method-call syntax is a calling
  convention. Non-`mutating` only (writes to properties are rejected like swiftc).
- **`protocol P { func req(...) -> T }`** declarations; struct conformance clauses `struct S: P`;
  the conformance CHECK with swiftc's diagnostic.
- **Existentials**: `P` / `any P` as a type = `{ [N x i64] payload, ptr witness_table }`; the
  implicit wrap at `let`/args/`return`/`=` (the protocol twin of optional wrapping); **dynamic
  dispatch** = load function pointer from table slot, call through a **thunk** that reloads the
  concrete `self`.
- Optimizer awareness: `Apply_witness` is a call (never CSE'd, blocks naive inlining); functions
  named in a witness table stay alive.

> **Scope (v0).** Method requirements only (no property/init/associated-type requirements);
> non-mutating methods; payload buffer sized to the largest conformer (heap-boxing of large
> values is concept 23). Two REAL shipped bugs were found building this — see the explainer:
> the Assign-wrap miscompile (13–20) and GVN's type-blind value key (18–20).

## Done when

`make lab C=phase5-generics/21-protocols-witness` is green. One cram file per hole —
`silgen-wtables.t`, `sema-conformance.t`, `silgen-wrap.t`, `silgen-dispatch.t` — plus the given
`sema-subset.t` and the headline `oracle.t`, which asks swiftc on every run: 33 programs where
`swiftc -typecheck` and `--typecheck` must agree on accept-or-reject, and 20 built four ways
(`swiftc -Onone`, `swiftc -O`, `./lab.exe build`, `./lab.exe build -O`) whose stdout and exit
code must be identical.
