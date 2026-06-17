# 12 · Pattern matching (`switch`)

**Objective:** add `switch` — Swift's pattern matcher — so enums become *usable*: read which case a
value is, **bind its associated values**, and run the matching arm, with **exhaustiveness** checking
that you can't forget a case. This is the destructuring counterpart to concept 11's construction; with
it, the tagged unions you built become real **ADTs**, and a tiny interpreter over an enum matches
swiftc.

**Prerequisites:** the enum compiler (concept 11), given and working.

**You edit (the two halves of pattern matching):**

- `silgen.ml` — `TODO(12)`: lower a `switch` to a **dispatch chain** — read the tag (`enum_tag`), then
  for each pattern a `tag == k ?` test (`cond_br`) to a case block that **binds the payload**
  (`enum_payload` → `alloc_stack` + `store`, like a `let`) and runs the body, all joining at a merge.
- `sema.ml` — `TODO(12-sema)`: the **exhaustiveness** check — with no `default`, every enum case must
  be matched, else "switch must be exhaustive" (matching swiftc).

Given: the contracts (patterns + the `Switch` stmt; SIL `Enum_payload`), the parser (switch/pattern
parsing), the pattern *typing* + payload *binding* in sema, and IRGen (`Enum_payload` →
`extractvalue`).

**Design oracle:** `../../../swift/lib/Sema/TypeCheckSwitchStmt.cpp` (exhaustiveness via space
algebra), `swift/lib/SILGen/SILGenPattern.cpp` (the decision tree), the SIL `switch_enum` terminator.

## What this concept adds

- `switch subject { case <pat>: <body> … [default: <body>] }` over an **enum** (patterns `.case`,
  `.case(let x, …)`, `_` bindings) or an **Int** (literal patterns + `default`).
- Exhaustiveness checking; the "missing return" analysis now treats an exhaustive all-returning switch
  as a definite return.
- SIL `Enum_payload` (read a payload slot) + the dispatch lowering.

> **Scope (v0).** Single pattern per `case`; no `where` clauses, tuple patterns, or `if let`/`guard`
> (those are concept 13's path and exercises here). The dispatch is a **linear** tag chain (a real
> compiler builds a balanced decision tree / jump table — see the explainer).

## Done when

`make lab C=phase3-value-types/12-pattern-matching` is green: the cram test **builds and runs** switch
programs — destructuring and a mini ADT interpreter — and the alcotest pins exhaustiveness, the
pattern rules, and the dispatch SIL (`enum_tag`/`enum_payload`/`cond_br`). Output matches `swiftc`.
