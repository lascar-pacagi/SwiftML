# Common tasks. Run from the `course/` directory.
# Prefer a local (no-sudo) Quarto in .tools/ if present, else a system `quarto`.
QUARTO := $(shell [ -x .tools/bin/quarto ] && echo .tools/bin/quarto || echo quarto)
# Python for figure generation: prefer the project venv (matplotlib lives there).
PY := $(shell [ -x .venv/bin/python ] && echo .venv/bin/python || echo python3)
# Run dune inside the opam switch so opam-installed libs (alcotest, …) are on the path —
# the toolchain is opam-managed even when a Homebrew `dune` is also on PATH. Falls back to a
# bare `dune` if opam isn't installed.
DUNE := $(shell command -v opam >/dev/null 2>&1 && echo "opam exec -- dune" || echo dune)

.PHONY: setup setup-hooks claim claim-all unclaim save restore check-pristine check-shipped build test test-all lab exercises oracle bench profile profile-cpu fmt lint figs explainer docs preview clean

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
	$(DUNE) build @$(C)/runtest --force

# Differential test a single program against swiftc:
#   make oracle F=tests/programs/arith.swift            (defaults to the Phase-1 swiftml)
#   make oracle F=prog.swift B=swiftml4                 (test a later phase's binary)
oracle:
	./tooling/oracle.sh $(F) $(B)

# Benchmark a concept (needs a bench/bench.ml — e.g. 01-lexer, 20-llvm-opt):
#   make bench C=phase4-optimizer/20-llvm-opt
bench:
	$(DUNE) exec -- ./$(C)/bench/bench.exe

# Run a concept's §6 EXERCISE tests (separate alias — RED until you do the exercises,
# and never part of `make lab`):
#   make exercises C=phase1-minimal/01-lexer
exercises:
	$(DUNE) build @$(C)/exercises --force

# Profile a concept's bench — "slow WHERE?" rather than "how fast?" (needs bench/profile.ml):
#   make profile C=phase1-minimal/01-lexer       per-construct cost, ablation ladder,
#                                                allocation accounting, allocation sites
#   make profile-cpu C=phase1-minimal/01-lexer   sampled call tree (macOS `sample`):
#                                                how much CPU is your code vs the GC
profile:
	$(DUNE) exec -- ./$(C)/bench/profile.exe

profile-cpu:
	@$(DUNE) build ./$(C)/bench/profile.exe
	@./tooling/profile-cpu.sh $(C) $(RUNG)

# ---- keeping your work out of the repo -------------------------------------
# You edit the skeletons in place, so your solutions live as uncommitted changes.
# Course corrections still commit normally; only the FILLED-IN files must stay local.
#   make setup-hooks     install the pre-commit guard (once, after cloning)
#   make save            snapshot your filled-in stage files into course/work/ (gitignored)
#   make restore C=<dir> put the pristine skeleton back (git restore)
#   make check-pristine  is HEAD safe for someone else to clone?
setup-hooks:
	@git -C .. config core.hooksPath course/tooling/hooks
	@echo "pre-commit guard installed (core.hooksPath=course/tooling/hooks)"

# Declare the stage files of a concept as YOUR work: the hook then refuses to commit them.
# Claim EVERY concept at once — the sensible default if you are working through the course
# and want none of your fill-ins to be committable.
claim-all:
	@for d in phase*/[0-9][0-9]-*; do test -d "$$d/solution" && $(MAKE) -s claim C=$$d; done
	@echo "all concepts claimed"

claim:
	@test -n "$(C)" || { echo "usage: make claim C=phase1-minimal/01-lexer (or: make claim-all)"; exit 1; }
	@mkdir -p work
	@for f in $(C)/*.ml; do \
	  test -f "$$f" || continue; \
	  sol=$(C)/solution/$$(basename $$f); \
	  if [ -f "$$sol" ] || grep -q 'TODO(' "$$f"; then \
	    grep -Fxq "course/$$f" work/.mine 2>/dev/null || echo "course/$$f" >> work/.mine; \
	    echo "  claimed course/$$f"; \
	  fi; \
	done
	@echo "guarded files are listed in course/work/.mine"

unclaim:
	@test -n "$(C)" || { echo "usage: make unclaim C=phase1-minimal/01-lexer"; exit 1; }
	@test -f work/.mine && grep -v "^course/$(C)/" work/.mine > work/.mine.tmp || true
	@mv -f work/.mine.tmp work/.mine 2>/dev/null || true
	@echo "no longer guarding $(C)"

# Snapshot the claimed files (they are the ones that must never be committed).
save:
	@test -f work/.mine || { echo "nothing claimed yet — see: make claim C=<dir>"; exit 0; }
	@n=0; while read -r p; do \
	  f=$${p#course/}; test -f "$$f" || continue; \
	  d=work/$$(dirname $$f); mkdir -p $$d; cp "$$f" "$$d"/; n=$$((n+1)); echo "  saved $$f"; \
	done < work/.mine; echo "$$n file(s) snapshotted under course/work/ (gitignored)"

restore:
	@test -n "$(C)" || { echo "usage: make restore C=phase1-minimal/01-lexer"; exit 1; }
	@git restore -- "$(C)"/*.ml && echo "restored the shipped skeletons in $(C)"

check-pristine:
	@./tooling/check-pristine.sh

# The real invariant, on what you would actually publish: check out HEAD into a throwaway
# worktree and confirm the concept's tests FAIL there (a skeleton that passes is a spoiler).
#   make check-shipped C=phase1-minimal/01-lexer
check-shipped:
	@test -n "$(C)" || { echo "usage: make check-shipped C=phase1-minimal/01-lexer"; exit 1; }
	@w=$$(mktemp -d)/head; git -C .. worktree add -q --detach $$w HEAD; \
	 if (cd $$w/course && $(DUNE) build @$(C)/runtest --force >/dev/null 2>&1); then \
	   echo "SPOILED: $(C) tests PASS on HEAD — the skeleton ships solved"; rc=1; \
	 else echo "ok — $(C) is RED on HEAD, as a skeleton should be"; rc=0; fi; \
	 git -C .. worktree remove --force $$w; exit $$rc

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
