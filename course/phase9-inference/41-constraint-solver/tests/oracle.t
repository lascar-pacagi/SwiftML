The oracle, and the reason this concept forks a pipeline that RUNS rather than one that stops
at `--typecheck`. Every program in `oracle-corpus.txt` is compiled by `swiftc` AND by your
compiler, both are run, and their output must match byte for byte.

Accept-or-reject is not enough here. `show(1.5)` type-checks whichever `show` you pick; only
running it tells `show#0` from `show#1`. Overload resolution is the one thing in this concept
that a weaker oracle cannot see at all.

  $ cat > oracle.sh <<'EOF'
  > #!/bin/sh
  > ok=0; bad=0; n=0
  > while IFS= read -r line; do
  >   case "$line" in ''|'#'*) continue ;; esac
  >   n=$((n+1))
  >   printf '%s\n' "$line" | tr '|' '\n' > p$n.swift
  >   err=$(./lab.exe build p$n.swift -o ours$n 2>&1 >/dev/null); rc=$?
  >   case "$err" in *'TODO(41'*) echo "$err" | head -1; exit 0 ;; esac
  >   if [ $rc -ne 0 ]; then bad=$((bad+1)); echo "OURS FAILED TO BUILD: $line"; continue; fi
  >   swiftc -O -o theirs$n p$n.swift >/dev/null 2>&1 || { echo "swiftc rejected: $line"; bad=$((bad+1)); continue; }
  >   a=$(./ours$n); b=$(./theirs$n)
  >   if [ "$a" = "$b" ]; then ok=$((ok+1)); else
  >     bad=$((bad+1)); echo "DIFFER on: $line"; echo "  ours:   $a"; echo "  swiftc: $b"; fi
  > done < oracle-corpus.txt
  > echo "match=$ok differ=$bad"
  > EOF
  $ sh oracle.sh
  match=10 differ=0
