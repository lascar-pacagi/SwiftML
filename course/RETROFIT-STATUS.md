# Ast → Tast retrofit — status

The decision and its reasoning are in `PLAN.md` §0.1. This file tracks where the work stands.

**Branch:** `tast-retrofit`, not merged. **Baseline:** tag `pre-tast-retrofit`.
Your working tree on `main` was never touched.

## Done — 16 of 36 concepts (05–20), each verified answer-key GREEN and skeleton RED

| concept | what moved into the tree | silgen |
|---|---|---|
| 05 | the literal coercion recorded; `Var`→`Local`, `Call`→`Print` | — |
| 06 | control-flow statements; block scope visible in the tree | — |
| 07 | `Call`→`Print`/`Fn_call`; signatures carry resolved types | — |
| 08 | (first consumer) | 445 → 384 |
| 09 | phase 2 end to end | — |
| 10 | `p.x`→field INDEX; `Point(x:1)`→`Struct_init`, labels discharged | 520 → 394 |
| 11 | `E.red`→`Enum_case` with the TAG — the shadowing rule, asked once | 376 → 313 |
| 12 | patterns→tags, bindings→types | +switch |
| 13 | **the implicit wrap becomes `Inject_optional`**; `Is_nil` | — |
| 14 | phase 3 complete | — |
| 15–20 | front end carried; block-args form from 16 | — |

Verified end to end: phase 2 compiles `let d = 1.5; print(d * 2)` (was
`error: integer constant must have integer type`); phase 3 runs shadowing + literal + optional
(`42`, `3`, `7`); phase 4 runs at `-O` (`45`, `3`); whole tree builds; `comparisons/` still 34/34.

## Remaining — 21–40

**21 is the next real one** and its design is worked out, just not written:

- `Tast.Erase of expr * string` — the existential wrap, swiftc's `ErasureExpr`, the protocol twin
  of 13's `Inject_optional`. Sema's `check_expr` already decides it; the comment there literally
  reads *"wrap: SILGen will init_existential"*, which is the whole problem in one line.
- `Tast.Static_method` vs `Tast.Witness_method` — a source-level `e.m(...)` is static dispatch on
  a struct and witness dispatch on `any P`, and only the receiver's type decides. Record which.
- `field_of_self` must return `(type, struct, INDEX)` so implicit self is spelled out in the tree.
- Watch for: implicit-self *writes* (`Assign` when `field_of_self` matches), the `site` ref that
  words one failure four ways, and `check_func` binding methods.

Then 22 (generics), 23 (`as?`/`as!`), 24 (opt.ml only — cheap), 25 (**`Upcast`**, the third
conversion), 26–28 (ARC), 29 (**closures** — the big one), 30–32, 33–37 (backend; front end
carried), 38–40.

`gen_expr_as` finally disappears once 13's, 21's and 25's conversions are all nodes. At concept 40
it has 28 call sites.

## The recipe

Per concept: copy the previous `tast.ml`, add that concept's new resolved nodes → port
`solution/sema.ml` so `infer`/`check_expr`/`check_stmt` return `Tast` values and `check` returns
`Tast.program option` → port `silgen.ml` to match on `Tast` → add `tast` to `dune`'s `modules`,
`Typed_ast` to `driver.ml`, `--emit-tast` to `tests/lab.ml` → run
`scratchpad/tools/fix_checkers.py <dir>` for the mechanical test call sites → verify GREEN with
every `solution/*.ml` overlaid → **then** carve the skeleton FROM the finished answer key and
verify RED.

Two things that cost me time, so they are written down:

- **Carve the skeleton last.** Overlaying solutions after carving destroys it (cost a rebuild on 07).
- **Port the answer-key driver too** where the hole is in `driver.ml` (concept 20): skeleton and
  solution diverge and both must move.
- When a concept is the previous one plus a feature (12 on 11, 14 on 13, 15–20 on 14), extend the
  already-ported file instead of re-porting its copy. Much less risk.

## Your work

Untouched, in four places: the live tree, `course/work/` (73 files), `course/work/.base/` (the
skeletons they are built on), and `stash@{0}` (`4b59b51`).

Eleven of your files are ones this branch also changes. When you merge:

    git merge-file <your file> course/work/.base/<path> <the retrofitted skeleton>
