#!/usr/bin/env bash
# Differential test against the behavioral oracle.
#
# Compile <file.swift> with BOTH our swiftml and the real swiftc, run both, and
# compare stdout + exit code. This is the headline correctness check of the whole
# project (the compiler analog of logit/grad parity).
#
#   usage: tooling/oracle.sh <file.swift> [swiftml-binary]
#
# The optional second argument picks which phase's compiler to test (swiftml = Phase 1,
# swiftml2/swiftml3/swiftml4 = later phases). Defaults to swiftml.
#
# Exit 0 = behavior matches. Exit 1 = divergence (prints a diff). Exit >1 = setup error.
set -uo pipefail

F="${1:-}"
BIN="${2:-swiftml}"
[[ -z "$F" ]] && { echo "usage: tooling/oracle.sh <file.swift> [swiftml|swiftml2|swiftml3|swiftml4]" >&2; exit 2; }
[[ -f "$F" ]] || { echo "no such file: $F" >&2; exit 2; }
command -v swiftc >/dev/null 2>&1 || {
  echo "swiftc not found (the behavioral oracle) — install Xcode / Command Line Tools" >&2; exit 3; }

# Run from the course/ root regardless of CWD.
cd "$(dirname "$0")/.." || exit 2
# Use the opam switch's toolchain (so opam-installed libs are found), like the Makefile.
eval "$(opam env 2>/dev/null)" || true
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

run_one () {  # run_one <label> <compile-cmd...> ; sets <label>_out / <label>_rc globals via files
  local label="$1"; shift
  if ! "$@" >"$tmp/$label.cerr" 2>&1; then
    printf 'compile-error' >"$tmp/$label.status"; : >"$tmp/$label.out"; echo 0 >"$tmp/$label.rc"; return
  fi
  printf 'ok' >"$tmp/$label.status"
  "$tmp/$label.bin" >"$tmp/$label.out" 2>&1; echo "$?" >"$tmp/$label.rc"
}

# Build swiftml once, then compile the program with it.
dune build 2>/dev/null || { echo "swiftml failed to build (dune build)" >&2; exit 4; }
run_one ref  swiftc "$F" -o "$tmp/ref.bin"
run_one mine dune exec --no-build "$BIN" -- build "$F" -o "$tmp/mine.bin"

rs=$(cat "$tmp/ref.status");  ms=$(cat "$tmp/mine.status")
rrc=$(cat "$tmp/ref.rc");     mrc=$(cat "$tmp/mine.rc")

ok=1
if [[ "$rs" != "$ms" ]]; then
  echo "DIVERGENCE: swiftc=$rs but swiftml=$ms (one compiled, the other didn't)"; ok=0
elif [[ "$rs" == "ok" ]]; then
  if ! diff -u "$tmp/ref.out" "$tmp/mine.out" >"$tmp/diff" ; then
    echo "DIVERGENCE in stdout (--- swiftc  +++ swiftml):"; cat "$tmp/diff"; ok=0
  fi
  if [[ "$rrc" != "$mrc" ]]; then
    echo "DIVERGENCE in exit code: swiftc=$rrc swiftml=$mrc"; ok=0
  fi
fi

if [[ $ok -eq 1 ]]; then
  echo "OK  $F  (status=$rs exit=$rrc)"; exit 0
else
  echo "----- swiftml compile output -----"; cat "$tmp/mine.cerr"
  if grep -q 'TODO(' "$tmp/mine.cerr"; then
    cat >&2 <<'HINT'

  ^ swiftml stopped at an unfinished concept. The oracle runs the WHOLE pipeline
    (lex -> parse -> sema -> IRGen -> clang -> run), so it cannot go green until
    codegen exists. While you are still in the front end, compare that instead:

        dune exec swiftml -- --typecheck FILE      vs      swiftc -typecheck FILE
HINT
  fi
  exit 1
fi
