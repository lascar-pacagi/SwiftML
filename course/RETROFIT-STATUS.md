# Ast → Tast retrofit — status

The decision and its reasoning are in `PLAN.md` §0.1. This file tracks where the work stands.

**Branch:** `tast-retrofit`. **Baseline:** tag `pre-tast-retrofit` (`git reset --hard` to undo).
Your working tree on `main` has NOT been touched: nothing in this branch is merged.

## Done (answer key green + skeleton RED, verified per concept)

| concept | what resolved into the tree | silgen |
|---|---|---|
| 05-types-inference | the literal coercion is recorded, `Var`→`Local`, `Call`→`Print` | — |
| 06-control-flow | control-flow statements; block scope visible in the tree | — |
| 07-functions | `Call`→`Print`/`Fn_call`; signatures carry resolved types | — |
| 08-sil-silgen | (consumer) | 445 → 384 |
| 09-sil-to-llvm | plumbing; phase 2 runs end to end | — |
| 10-structs | `p.x`→field INDEX; `Point(x:1)`→`Struct_init`, labels discharged | 520 → 394 |
| 11-enums-adts | `E.red`→`Enum_case` with the TAG — the shadowing rule, asked once | 376 → 313 |

Phase 2 verified end to end: `let d = 1.5; print(d * 2)` compiles and runs under `swiftml2`,
which it did not before (`error: integer constant must have integer type`).

## Remaining

12-pattern-matching, 13-optionals, 14-memory-layout, then 15–40.

From 13 onward the CONVERSIONS start: `Inject_optional` (13), `Erase` (21), `Upcast` (25).
Those are what finally delete `gen_expr_as`, which at concept 40 has 28 call sites.

## The recipe, if you want to continue it yourself

Per concept: copy the previous `tast.ml` and add that concept's new resolved nodes → port
`solution/sema.ml` so `infer`/`check_expr`/`check_stmt` return `Tast` values and `check` returns
`Tast.program option` → port `silgen.ml` to match on `Tast` → add `tast` to `dune`'s `modules`,
add `Typed_ast` to `driver.ml` and `--emit-tast` to `tests/lab.ml` → fix test call sites
(`scratchpad/tools/fix_checkers.py` does the mechanical ones) → verify GREEN with every
`solution/*.ml` overlaid, then carve the skeleton FROM the ported solution and verify RED.

Carve the skeleton LAST, from the finished answer key. Overlaying solutions after carving
destroys it — that cost me a rebuild on 07.

## Your work

Untouched, in four places: the live tree, `course/work/` (73 files), `course/work/.base/`
(the skeletons they are built on), and `stash@{0}` (`4b59b51`).

When you merge this branch, the eleven files you have edited need a 3-way merge:

    git merge-file <your file> course/work/.base/<path> <the retrofitted skeleton>
