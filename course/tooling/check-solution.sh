#!/usr/bin/env bash
# Build a concept against its ANSWER KEY and run its tests.
#
#   make check-solution C=phase2-types-flow/05-types-inference
#
# Nothing else in the course ever compiles solution/, so a reference can rot silently — that is
# how `solution/token.ml` came to be missing a keyword the skeleton had. Run the answer key in a
# detached worktree: replacing files in the learner's live checkout, even briefly, races with an
# editor or a second `make lab`.
set -u
C="${C:-}"
[ -n "$C" ] || { echo "usage: make check-solution C=<concept dir>"; exit 2; }
[ -d "$C/solution" ] || { echo "$C has no solution/ — nothing to check"; exit 0; }

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREE="$(mktemp -d)"
FILES=""
cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  rm -rf "$WORKTREE"
}
trap cleanup EXIT INT TERM

git -C "$REPO_ROOT" worktree add --quiet --detach "$WORKTREE" HEAD || exit $?
WORK_C="$WORKTREE/course/$C"

# Fill every concept first: this one's tests link the chain below it, and a prerequisite
# still on its skeleton would leave every case reading TODO rather than exercising the
# key under test. The concept under test is then re-filled from its own solution/ below.
. "$REPO_ROOT/course/tooling/fill-solutions.sh"
fill_solutions "$WORKTREE/course"

for sol in "$WORK_C"/solution/*.ml; do
  f="$(basename "$sol")"
  [ -f "$WORK_C/$f" ] || continue     # solution-only files (e.g. a v1 rung) are not copied in
  cp "$sol" "$WORK_C/$f"
  FILES="$FILES $f"
done
[ -n "$FILES" ] || { echo "$C: solution/ has no counterpart in the concept dir"; exit 0; }
echo "check-solution: isolated answer key:$FILES"

# Use the same runner as the learner. Besides keeping the report identical, this preserves any
# staged test order declared by the concept.
(cd "$WORKTREE/course" && make -s lab C="$C")
rc=$?

if [ $rc -eq 0 ]; then echo; echo "ANSWER KEY OK — $C passes its own tests"
else echo; echo "ANSWER KEY BROKEN — $C does not pass its own tests (exit $rc)"; fi
exit $rc
