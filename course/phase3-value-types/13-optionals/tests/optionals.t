End-to-end: optionals are an enum — compile with ./lab.exe and RUN, matching swiftc (including
the force-unwrap trap). RED until SILGen's TODO(13) holes are filled.

`if let`, `??`, `!`, and `== nil` all run:

  $ cat > o.swift <<'EOF'
  > let a: Int? = 5
  > let b: Int? = nil
  > if let v = a { print(v) }
  > print(b ?? 99)
  > print(a!)
  > print(a == nil)
  > print(b == nil)
  > EOF
  $ ./lab.exe build o.swift -o o && ./o
  5
  99
  5
  false
  true

A function returning `Int?` wraps a bare value, and `nil` flows through `??`:

  $ cat > f.swift <<'EOF'
  > func f(_ n: Int) -> Int? {
  >   if n < 0 { return nil }
  >   return n * 2
  > }
  > if let r = f(5) { print(r) }
  > print(f(-1) ?? -1)
  > EOF
  $ ./lab.exe build f.swift -o f && ./f
  10
  -1

Reassigning an optional VAR wraps too (a once-shipped miscompile: the raw `7` was stored
unwrapped, so `x ?? 0` saw a corrupt tag and printed 0 — this line pins the fix):

  $ printf 'var x: Int? = 5\nx = 7\nprint(x ?? 0)\n' > r.swift
  $ ./lab.exe build r.swift -o r && ./r
  7

Force-unwrapping `nil` traps — same exit code (133 = 128 + SIGTRAP from `llvm.trap`) as swiftc's
runtime failure. (The wrapper shell exists so the nondeterministic "Trace/BPT trap: <pid>" job
message lands on a redirected stderr instead of in this transcript.)

  $ printf 'let x: Int? = nil\nprint(x!)\n' > t.swift
  $ ./lab.exe build t.swift -o t
  $ sh -c './t; echo "exit=$?"' 2>/dev/null
  exit=133

An optional is laid out as `{ tag, payload }`:

  $ ./lab.exe --emit-llvm o.swift | grep -q "{ i64, i64 }" && echo "optional = { i64 tag, i64 payload }"
  optional = { i64 tag, i64 payload }
