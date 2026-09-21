#!/usr/bin/env bash
# Copy every concept's answer key over its skeleton, inside a throwaway worktree.
#
# Sourced by check-solution.sh and check-exercises.sh. A concept's tests link the whole
# chain below it — 04's lab.exe needs 01/02/03 — so filling only the concept under test
# leaves it blocked by someone else's TODO and every case reads `TODO` instead of PASS.
# The concept under test is then re-filled by the caller, from whichever key it wants.
fill_solutions() {
  local root="$1"
  local sol f dir
  for sol in "$root"/*/*/solution/*.ml; do
    [ -f "$sol" ] || continue
    dir="$(dirname "$(dirname "$sol")")"
    f="$(basename "$sol")"
    # solution-only files (a v1 rung, say) have no skeleton to replace
    [ -f "$dir/$f" ] && cp "$sol" "$dir/$f"
  done
  return 0
}
