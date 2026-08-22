#!/usr/bin/env bash
# Is this tree safe for someone else to clone?
#
#   make check-pristine
#
# Checks what will actually be published (HEAD), and separately reports what is only in
# your working tree. Two failure modes matter:
#   1. a skeleton committed with its holes filled  — the exercise arrives pre-solved;
#   2. a skeleton byte-identical to its solution/  — same thing, by a different route.
set -uo pipefail
cd "$(dirname "$0")/.."

status=0

echo "== committed skeletons (HEAD) =="
spoiled=0
for sol in $(git ls-files 'phase*/*/solution/*.ml'); do
  f=$(printf '%s' "$sol" | sed 's|/solution/|/|')
  if ! git cat-file -e "HEAD:course/$f" 2>/dev/null; then
    echo "   ?        $f has a solution/ copy but no committed skeleton"
    status=1
    continue
  fi
  if git show "HEAD:course/$f" | diff -q - <(git show "HEAD:course/$sol") >/dev/null 2>&1; then
    echo "   SPOILED  $f is byte-identical to its solution/"
    spoiled=$((spoiled + 1))
  fi
done
if [ "$spoiled" -eq 0 ]; then
  echo "   ok — no skeleton matches its answer key"
else
  echo "   $spoiled skeleton(s) ship pre-solved"
  status=1
fi

echo
echo "== your working tree =="
dirty=$(git status --porcelain -- . | wc -l | tr -d ' ')
if [ "$dirty" -eq 0 ]; then
  echo "   clean"
else
  echo "   $dirty path(s) uncommitted — fine if these are the exercises you are solving:"
  git status --porcelain -- . | sed 's/^/     /'
fi

exit $status
