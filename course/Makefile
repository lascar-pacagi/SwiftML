# Common tasks. Run from the `course/` directory.
# Prefer a local (no-sudo) Quarto in .tools/ if present, else a system `quarto`.
QUARTO := $(shell [ -x .tools/bin/quarto ] && echo .tools/bin/quarto || echo quarto)
# Python for figure generation: prefer the project venv (matplotlib lives there).
PY := $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)
# Run dune inside the opam switch so opam-installed libs (alcotest, …) are on the path —
# the toolchain is opam-managed even when a Homebrew `dune` is also on PATH. Falls back to a
# bare `dune` if opam isn't installed.
DUNE := $(shell command -v opam >/dev/null 2>&1 && echo "opam exec -- dune" || echo dune)

.PHONY: setup build test test-all lab oracle bench fmt lint figs explainer docs preview clean

# ---- Phase 0: toolchain bootstrap ------------------------------------------
# Installs OCaml + dune + the test/format deps. Walks you through opam if missing.
setup:
	@command -v opam >/dev/null 2>&1 || { \
	  echo "opam not found. Install it first:"; \
	  echo "    brew install opam && opam init -y && eval \$$(opam env)"; \
	  exit 1; }
	opam install -y dune alcotest ocamlformat
	@echo "Toolchain ready. Now run: make build"

# ---- build & run -----------------------------------------------------------
build:
	$(DUNE) build

# The CLI:  dune exec swiftml -- build foo.swift   (or --emit-tokens/-ast/-sil/-llvm/-asm)
run:
	$(DUNE) exec swiftml -- $(ARGS)

# ---- tests -----------------------------------------------------------------
# ALL concept tests (cram + alcotest, every phase). On the shipped tree this is RED by design —
# the skeletons' TODO holes fail their own tests. Use `make lab C=<concept>` while working.
test:
	$(DUNE) build @runtest

# Build everything, then run all tests.
test-all:
	$(DUNE) build @all @runtest

# Run just one concept's tests against your in-progress code in that directory:
#   make lab C=phase1-minimal/01-lexer
# (The concept's cram tests run ./lab.exe, built from THAT concept's library.)
lab:
	$(DUNE) build @$(C)/runtest

# Differential test a single program against swiftc:
#   make oracle F=tests/programs/arith.swift            (defaults to the Phase-1 swiftml)
#   make oracle F=prog.swift B=swiftml4                 (test a later phase's binary)
oracle:
	./tooling/oracle.sh $(F) $(B)

# Benchmark a concept (needs a bench/bench.ml — e.g. 01-lexer, 20-llvm-opt):
#   make bench C=phase4-optimizer/20-llvm-opt
bench:
	$(DUNE) exec -- ./$(C)/bench/bench.exe

# ---- formatting ------------------------------------------------------------
# Needs ocamlformat in the opam switch (`opam install ocamlformat` — `make setup` includes it).
fmt:
	$(DUNE) fmt

lint:
	$(DUNE) build @fmt

# ---- docs (Quarto) ---------------------------------------------------------
# Generate a concept's real figures from its figs/make_figs.py (matplotlib/graphviz).
# Every explainer that references figs/*.png MUST ship the generator + the image — we never
# leave "(figure to be generated)" stubs, and `explainer`/`explainer-pdf` regenerate first so
# figures are always current. No-op (with a note) for concepts that have no figures.
figs:
	@if [ -f "$(C)/figs/make_figs.py" ]; then \
	  echo "figs: $(PY) $(C)/figs/make_figs.py"; $(PY) "$(C)/figs/make_figs.py"; \
	else echo "figs: (none for $(C))"; fi

# Render one concept's explainer to HTML:  make explainer C=phase1-minimal/01-lexer
# (Figures are regenerated first via the `figs` prerequisite, so PDF/Typst always has them.)
explainer: figs
	$(QUARTO) render $(C)/explainer.qmd --to html

docs:
	$(QUARTO) render --to html

explainer-pdf: figs
	$(QUARTO) render $(C)/explainer.qmd --to typst

docs-pdf:
	$(QUARTO) render --to typst

preview:
	$(QUARTO) preview

# ---- housekeeping ----------------------------------------------------------
clean:
	$(DUNE) clean
