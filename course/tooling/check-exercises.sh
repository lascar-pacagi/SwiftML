#!/usr/bin/env bash
# Build a concept against its EXERCISE answer key and run its tests.
#
#   make check-exercises C=phase1-minimal/04-codegen
#
# solution/exercises/ holds the stage modules with §6's exercises APPLIED, so the code the
# explainer's §9 quotes is code that compiles and runs. Two things are checked at once:
#   - the exercises themselves, via tests/test_exercises.ml, whose groups activate only
#     when they see the lowering change;
#   - that the concept's OWN suite still passes with the exercises in, which is what
#     "unit tests stay exercise-neutral" means in practice.
# Same detached worktree as check-solution: the learner's live checkout is never touched.
set -u
C="${C:-}"
[ -n "$C" ] || { echo "usage: make check-exercises C=<concept dir>"; exit 2; }
if [ ! -d "$C/solution/exercises" ]; then
  echo "$C has no solution/exercises/ — nothing to check. Concepts that do:"
  (cd "$(git rev-parse --show-toplevel)/course" && \
    find . -type d -name exercises -path '*/solution/*' | sed 's|^\./||;s|/solution/exercises$||' | sort | sed 's/^/  /')
  exit 0
fi

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

# Start from the stock answer key everywhere — this concept's tests link the chain below
# it — then let solution/exercises/ override the modules it carries: an exercise usually
# touches one stage, and the rest must still be answered.
. "$REPO_ROOT/course/tooling/fill-solutions.sh"
fill_solutions "$WORKTREE/course"
for sol in "$WORK_C"/solution/exercises/*.ml; do
  f="$(basename "$sol")"
  [ -f "$WORK_C/$f" ] || { echo "$C: solution/exercises/$f has no counterpart in the concept dir"; exit 2; }
  cp "$sol" "$WORK_C/$f"
  FILES="$FILES $f"
done
[ -n "$FILES" ] || { echo "$C: solution/exercises/ holds no .ml files"; exit 0; }
echo "check-exercises: isolated exercise key:$FILES"

(cd "$WORKTREE/course" && make -s lab C="$C")
rc=$?

if [ $rc -eq 0 ]; then echo; echo "EXERCISE KEY OK — $C passes its own tests with §6 applied"
else echo; echo "EXERCISE KEY BROKEN — $C does not pass with §6 applied (exit $rc)"; fi
exit $rc
