# 00 · setup — toolchain & the harness ("hello, exit code")

**Objective:** stand up the OCaml toolchain, build the `swiftml` skeleton, and prove the *whole
pipeline* end-to-end on the most trivial possible language: a program that is a single integer,
whose value becomes the process exit code. This is **Milestone M0** — the loop works before we
teach any real compiler theory.

**Prerequisites:** none. You're a pro coder; this is plumbing.

## 1. Install the toolchain

```bash
# opam (the OCaml package manager) — one time
brew install opam
opam init -y            # sets up ~/.opam; follow the prompt to add the shell hook
eval "$(opam env)"

# project deps
cd course
make setup              # opam install dune alcotest ocamlformat
```

> `make setup` errors out with these exact instructions if `opam` is missing. Use a recent OCaml
> (`opam switch create 5.2.0` if you want an isolated switch).

## 2. Build the skeleton

```bash
make build              # dune build
```

> **Note:** this bootstrap concept is the standard's one deliberate exception — no
> `explainer.qmd`, no `tests/` (its definition of done is the toolchain working and `swiftml-m0`
> compiling a program, verified by running it). Every numbered concept from `01-lexer` on follows
> the full structure: explainer + tests + solution + figs.

The scaffolded stage modules (in each concept directory) are **skeletons** (`failwith "TODO(NN): …"`). The data
contracts (`token.ml`, `ast.ml`, `diagnostics.ml`) and the wiring (`driver.ml`, `bin/main.ml`)
are written; the algorithmic functions (`lexer.next`, `parser.parse_*`, `sema.check`,
`irgen.emit_llvm`) are yours, starting in Phase 1. The scaffold compiles clean
(`dune build` is green) — running any inspection flag fires the relevant `TODO` until you
implement it, which is exactly the "red → green" loop you'll follow in Phase 1.

## 3. The M0 vertical slice — **already implemented for you**

To prove the whole pipeline works *before* the real lexer/parser exist, this directory is itself a
tiny **self-contained** compiler (`main.ml` here, ~50 lines, building the `swiftml-m0` binary) for
the trivial language *"a program is a single integer literal; its value is the process exit code."*
It depends on nothing else — you delete it once Phase 1's real pipeline subsumes it.

```bash
printf '7\n' > seven.swift
dune exec swiftml-m0 -- seven.swift -o seven    # source -> LLVM IR -> clang -> arm64 exe
./seven ; echo $?                                # => 7
file seven                                       # => Mach-O 64-bit executable arm64
```

`main.ml` emits exactly:

```llvm
define i32 @main() {
entry:
  ret i32 7
}
```

and the driver runs it through `clang` (which assembles + links a native executable).

**Why the identical-file oracle waits for M1.** Real Swift's process exit code comes from
`exit(_:)`/`main`'s return, not from a bare top-level expression — `swiftc` compiles a file
containing just `7` to an exe that exits `0` (the literal is discarded, with a warning). So at M0 we
verify our exit-code *model* matches Swift's, rather than diffing the identical file:

```bash
printf 'import Foundation\nexit(7)\n' > exit7.swift
swiftc exit7.swift -o exit7_ref && ./exit7_ref ; echo $?   # => 7, same as swiftml m0
```

The full `make oracle F=…` identical-file parity comes online at **M1**, where Phase-1 programs
`print` and the source is genuinely the same for both compilers.

## 4. Definition of done (M0) — ✅ verified at bootstrap

- `dune build` is clean; the Phase-1 cram tests **run** (red on their `TODO`s, which is correct).
- `swiftml-m0 <int>.swift` produces a real native **arm64 Mach-O** executable via clang.
- Its exit code is the integer; `swiftc`'s `exit(N)` yields the same code (semantics match).

This proves the loop: **OCaml → swiftml-m0 → LLVM IR → clang → arm64 exe → run.** Everything after
this just makes the language bigger and the code faster. Move on to `phase1-minimal/01-lexer`.
