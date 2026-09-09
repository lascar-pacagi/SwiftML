#!/usr/bin/env bash
# Build a concept against its ANSWER KEY and run its tests.
#
#   make check-solution C=phase2-types-flow/05-types-inference
#
# Nothing else in the course ever compiles solution/, so a reference can rot silently — that is
# how `solution/token.ml` came to be missing a keyword the skeleton had. This swaps each
# solution/<f>.ml over <f>.ml, runs the concept's tests, and puts the originals back.
#
# The learner's work is copied aside FIRST and restored by a trap, so an interrupt or a failing
# build cannot leave the swap in place.
set -u
C="${C:-}"
[ -n "$C" ] || { echo "usage: make check-solution C=<concept dir>"; exit 2; }
[ -d "$C/solution" ] || { echo "$C has no solution/ — nothing to check"; exit 0; }

BAK="$(mktemp -d)"
FILES=""
restore() {
  for f in $FILES; do [ -f "$BAK/$f" ] && cp "$BAK/$f" "$C/$f"; done
  rm -rf "$BAK"
}
trap restore EXIT INT TERM

for sol in "$C"/solution/*.ml; do
  f="$(basename "$sol")"
  [ -f "$C/$f" ] || continue          # solution-only files (e.g. a v1 rung) are not swapped in
  cp "$C/$f" "$BAK/$f"; FILES="$FILES $f"
  cp "$sol" "$C/$f"
done
[ -n "$FILES" ] || { echo "$C: solution/ has no counterpart in the concept dir"; exit 0; }
echo "check-solution: swapped$FILES"

# Use the same runner as the learner.  Besides keeping the report identical, this
# preserves any staged test order declared by the concept.
make -s lab C="$C"
rc=$?

if [ $rc -eq 0 ]; then echo; echo "ANSWER KEY OK — $C passes its own tests"
else echo; echo "ANSWER KEY BROKEN — $C does not pass its own tests (exit $rc)"; fi
exit $rc
