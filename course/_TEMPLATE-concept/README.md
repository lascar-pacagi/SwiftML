# NN · <concept-name>

**Objective:** <one or two sentences: what part of the compiler you build here.>

**Prerequisites:** <previous concepts.>

**You edit:** `<module>.ml` (in this directory; the function(s) listed below). This concept is a
stage library that depends on the previous stage; the phase's `bin/` links it into `swiftml`.
**Design oracle:** `../../swift/lib/<...>` — read it.

## Versions (the progressive ladder)

| Version | What changes | Correctness | Perf |
|---|---|---|---|
| `v0_naive` | <first correct implementation> | <check> | — |
| `v1_<step>` | <one optimization step> | <check> | <gate> |

(Not every concept has many versions; perf-heavy ones — register allocation, optimizer passes —
have several. Keep each rung runnable.)

## Workflow

1. **Read** `explainer.qmd` (render: `make explainer C=<this-dir>`).
2. **Implement** the `TODO(NN)` functions in this directory's `<module>.ml`, guided by the explainer §3.
3. **Test** as you go: `make lab C=<this-dir>` — one `.t` per hole goes green as you fill it, and
   `tests/oracle.t` re-asks `swiftc` about every program in `oracle-corpus.txt` on every run.
4. **Bench** (perf concepts): `make bench C=<this-dir>`.

**Definition of done:** `make lab` green, behavior matches `swiftc`, any perf gate met, explainer
renders. Then freeze the verified modules into `solution/` and move on.

## Instantiating the template

Copy this directory, then: rename `dune.template`/`tests/dune.template` to `dune` (replacing
`CONCEPT` with the concept's library suffix), rename `tests/example.t.template` to a real cram
file per hole and `tests/oracle.t.template` to `oracle.t` (with an `oracle-corpus.txt`), write
`tests/lab.ml` (copy the previous concept's — it's the per-concept CLI the cram tests
run), replace `figs/make_figs.py`'s example with the real diagram, and keep verified answers in
`solution/` (see `solution/README.template.md`).
