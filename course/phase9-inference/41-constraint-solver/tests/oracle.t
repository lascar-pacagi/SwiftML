The oracle. Every program in `oracle-corpus.txt` goes through `swiftc -typecheck` AND through
your solver, and the two must AGREE about accepting or rejecting it. Nothing in the corpus is
outside real Swift — overloading on parameter types, overloading on the return type alone,
literal defaulting — so `swiftc` is entitled to an opinion about all of it.

This is the test that says the concept is a type checker and not a plausible-looking search.

  $ cat > oracle.sh <<'EOF'
  > #!/bin/sh
  > ok=0; bad=0
  > while IFS= read -r line; do
  >   case "$line" in ''|'#'*) continue ;; esac
  >   printf '%s\n' "$line" | tr '|' '\n' > p.swift
  >   swiftc -typecheck p.swift >/dev/null 2>&1; theirs=$?
  >   err=$(./lab.exe --typecheck p.swift 2>&1 >/dev/null); ours=$?
  >   # an unwritten hole is not a disagreement: stop, so the runner reads TODO not FAIL
  >   case "$err" in *'TODO(41'*) echo "$err" | head -1; exit 0 ;; esac
  >   t=reject; [ $theirs -eq 0 ] && t=accept
  >   o=reject; [ $ours -eq 0 ] && o=accept
  >   if [ "$t" = "$o" ]; then ok=$((ok+1)); else
  >     bad=$((bad+1)); echo "DISAGREE ($t vs $o): $line"; fi
  > done < oracle-corpus.txt
  > echo "agree=$ok disagree=$bad"
  > EOF
  $ sh oracle.sh
  agree=14 disagree=0
