#!/usr/bin/env bash
# A tiny FileCheck, for asserting the *shape* of --emit-tokens/-ast/-sil/-llvm and
# diagnostics. If LLVM's real `FileCheck` is on PATH (e.g. after `brew install llvm`),
# we defer to it; otherwise we use a minimal built-in that supports:
#
#   // CHECK:     <substr>     the substr must appear, on/after the previous match's line
#   // CHECK-NEXT:<substr>     must appear on the very next output line
#   // CHECK-NOT: <substr>     must NOT appear before the next CHECK
#
#   usage:  <producer> | tooling/filecheck.sh <checkfile>
#
# Reads the program-under-check's output on stdin; the CHECK lines live in <checkfile>.
set -uo pipefail

CHECKS="${1:?usage: filecheck.sh <checkfile>}"

if command -v FileCheck >/dev/null 2>&1; then
  exec FileCheck "$CHECKS"
fi

input="$(cat)"
mapfile -t out <<<"$input"

# Extract the directives in order.
i=0 line_idx=0 fail=0
while IFS= read -r raw; do
  dir=""; pat=""
  if   [[ "$raw" =~ CHECK-NEXT:[[:space:]]*(.*)$ ]]; then dir="NEXT"; pat="${BASH_REMATCH[1]}"
  elif [[ "$raw" =~ CHECK-NOT:[[:space:]]*(.*)$  ]]; then dir="NOT";  pat="${BASH_REMATCH[1]}"
  elif [[ "$raw" =~ CHECK:[[:space:]]*(.*)$      ]]; then dir="CHECK"; pat="${BASH_REMATCH[1]}"
  else continue; fi
  pat="${pat%$'\r'}"

  case "$dir" in
    CHECK)
      found=0
      while (( line_idx < ${#out[@]} )); do
        if [[ "${out[$line_idx]}" == *"$pat"* ]]; then found=1; ((line_idx++)); break; fi
        ((line_idx++))
      done
      (( found )) || { echo "CHECK failed: '$pat' not found"; fail=1; } ;;
    NEXT)
      if (( line_idx < ${#out[@]} )) && [[ "${out[$line_idx]}" == *"$pat"* ]]; then ((line_idx++))
      else echo "CHECK-NEXT failed: '$pat' not on line $((line_idx+1))"; fail=1; fi ;;
    NOT)
      for (( j=line_idx; j<${#out[@]}; j++ )); do
        [[ "${out[$j]}" == *"$pat"* ]] && { echo "CHECK-NOT failed: '$pat' present"; fail=1; break; }
      done ;;
  esac
done <"$CHECKS"

(( fail )) && { echo "---- actual output ----"; printf '%s\n' "${out[@]}"; exit 1; }
echo "FileCheck OK"; exit 0
