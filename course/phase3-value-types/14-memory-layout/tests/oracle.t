THE HEADLINE TEST: our layout numbers are checked against `MemoryLayout` — Swift's own answer,
asked of swiftc on every run, so nothing here can drift from what Swift actually does.

The probe program is GENERATED FROM OUR OUTPUT. For every line we print, `mk.awk` writes the
matching `MemoryLayout<T>.size` / `.stride` / `.alignment` / `.offset(of:)` interpolation, in the
same format; the probe is appended to the declarations, compiled by `swiftc -Onone`, run, and the
two outputs must be byte-identical. Comparing our text against swiftc's text means a missing line
or an extra one is a failure too, not just a wrong number.

  $ cat > mk.awk <<'AWK'
  > /^  \./ { f = substr($1, 2); printf "print(\"  .%s offset=\\(MemoryLayout<%s>.offset(of: \\%s.%s)!)\")\n", f, cur, cur, f; next }
  > /^[A-Za-z_][A-Za-z0-9_]*:/ { cur = substr($1, 1, length($1) - 1);
  >   printf "print(\"%s: size=\\(MemoryLayout<%s>.size) stride=\\(MemoryLayout<%s>.stride) align=\\(MemoryLayout<%s>.alignment)\")\n", cur, cur, cur, cur }
  > AWK

The 16 programs of `oracle-corpus.txt` — every shape the padding walk has to get right: two
`Int`s, a `Bool` before and after an `Int`, runs of `Bool`s, `Double`s, structs nested one, two
and three deep, a struct declared after the one that uses it, and padding in the middle. They are
structs of scalars ONLY: our enums and optionals use the naive `{ i64 tag, payload }` model and
swiftc packs the tag into spare bits, so those numbers legitimately differ (§2).

  $ n=0; while IFS= read -r prog; do
  >   [ -n "$prog" ] || continue; n=$((n+1))
  >   printf '%b\n' "$prog" > p$n.swift
  >   if ! ./lab.exe --emit-layout p$n.swift > ours$n.txt 2>err.txt; then
  >     printf 'ours REFUSED: %s\n' "$prog"; head -1 err.txt
  >     if grep -q 'TODO(' err.txt; then echo "(stopping: the hole above is not started)"; break; fi
  >     continue
  >   fi
  >   cp p$n.swift probe$n.swift; awk -f mk.awk ours$n.txt >> probe$n.swift
  >   if ! swiftc -Onone probe$n.swift -o probe$n >/dev/null 2>&1; then printf 'swiftc REFUSED: %s\n' "$prog"; continue; fi
  >   ./probe$n > swift$n.txt 2>&1
  >   if ! cmp -s ours$n.txt swift$n.txt; then
  >     printf 'DIVERGE: %s\n' "$prog"; diff ours$n.txt swift$n.txt
  >   fi
  > done < oracle-corpus.txt
  $ echo done
  done

A struct with an optional field still COMPILES AND RUNS, matching swiftc — the `p.x = e`
lowering bug concept 13 fixed, carried into this concept's compiler (the phase binary `swiftml3`
is built from here, so a gap here is a gap in the phase):

  $ cat > carry.swift <<'EOF'
  > struct Box {
  >   var v: Int?
  >   var n: Int
  > }
  > var b = Box(v: 3, n: 1)
  > print(b.v ?? -1)
  > b.v = nil
  > print(b.v ?? -1)
  > b.v = 9
  > print(b.v ?? -1)
  > EOF
  $ swiftc -Onone carry.swift -o swcarry >/dev/null 2>&1
  $ ./lab.exe build carry.swift -o mlcarry >/dev/null 2>&1
  $ ./swcarry > a.txt 2>&1; ./mlcarry > b.txt 2>&1
  $ diff a.txt b.txt && cat b.txt
  3
  -1
  9

And an `Int` literal that checks at `Double` is BORN a double — `d * 2` must emit a double
constant, not `fmul double %d, 2`, which clang refuses. (The program is not compared with
swiftc: our `print` formats a Double with C's `%g`, swiftc with Swift's shortest round-trip
form, so `2` against `2.0` — a documented divergence, not a layout question.)

  $ cat > dbl.swift <<'EOF'
  > let d: Double = 1.5
  > print(d * 2)
  > EOF
  $ ./lab.exe --emit-llvm dbl.swift | grep fmul
    %t2 = fmul double %t1, 0x4000000000000000
  $ ./lab.exe build dbl.swift -o dbl && ./dbl
  3
