The programs of concept 13, BUILT and RUN — including the trap, which is the only place an exit
code carries meaning. It needs all four silgen holes; `oracle.t` checks the same kind of program
against swiftc on every run.

`if let`, `??`, `!` and `== nil` all run, on a `.some` and on a `.none`:

  $ cat > o.swift <<'EOF'
  > let a: Int? = 5
  > let b: Int? = nil
  > if let v = a { print(v) }
  > if let v = b { print(v) } else { print(-1) }
  > print(a ?? 99)
  > print(b ?? 99)
  > print(a!)
  > print(a == nil)
  > print(b == nil)
  > EOF
  $ ./lab.exe build o.swift -o o && ./o
  5
  -1
  5
  99
  5
  false
  true

A function returning `Int?` wraps a bare value at `return`, and its `nil` flows through `??`:

  $ cat > f.swift <<'EOF'
  > func f(_ n: Int) -> Int? {
  >   if n < 0 { return nil }
  >   return n * 2
  > }
  > if let r = f(5) { print(r) }
  > print(f(-1) ?? -1)
  > print(f(3)!)
  > EOF
  $ ./lab.exe build f.swift -o f && ./f
  10
  -1
  6

Reassigning an optional `var` wraps too — the once-shipped miscompile, pinned: the raw `7` used
to be stored unwrapped, so `x ?? 0` read a corrupt tag and printed 0:

  $ printf 'var x: Int? = 5\nx = 7\nprint(x ?? 0)\nx = nil\nprint(x ?? 0)\n' > r.swift
  $ ./lab.exe build r.swift -o r && ./r
  7
  0

An optional lives in a struct field and survives the copy that value semantics makes:

  $ cat > box.swift <<'EOF'
  > struct Box {
  >   var v: Int?
  >   var n: Int
  > }
  > var b = Box(v: 3, n: 1)
  > var c = b
  > c.v = nil
  > print(b.v ?? -1)
  > print(c.v ?? -1)
  > print(c.n)
  > EOF
  $ ./lab.exe build box.swift -o box && ./box
  3
  -1
  1

Optionals inside a loop: `if let` filters, `??` supplies a default, and the totals agree:

  $ cat > loop.swift <<'EOF'
  > func even(_ n: Int) -> Int? {
  >   if n % 2 == 0 { return n }
  >   return nil
  > }
  > var i = 0
  > var s = 0
  > var t = 0
  > while i < 6 {
  >   if let v = even(i) { s = s + v }
  >   t = t + (even(i) ?? 0)
  >   i = i + 1
  > }
  > print(s)
  > print(t)
  > EOF
  $ ./lab.exe build loop.swift -o loop && ./loop
  6
  6

Force-unwrapping `nil` TRAPS, with swiftc's own message on stderr and exit 133 (128 + SIGTRAP,
which is what `llvm.trap` raises). The `sh -c` wrapper keeps the shell's nondeterministic
"Trace/BPT trap: <pid>" job message out of this transcript:

  $ printf 'let x: Int? = nil\nprint(x!)\n' > t.swift
  $ ./lab.exe build t.swift -o t
  $ sh -c './t; echo "exit=$?"' 2>/dev/null
  exit=133

The message on stderr is the one Swift prints:

  $ sh -c './t 2>msg.txt' 2>/dev/null; head -1 msg.txt
  Fatal error: Unexpectedly found nil while unwrapping an Optional value

An `Int?` is the ANONYMOUS aggregate `{ i64, i64 }` in LLVM — tag then payload, the naive
layout, 16 bytes; swiftc packs the tag into the payload's spare bits and gets 9 (§2). Its slot
is an `alloca` of that shape, and the tag is `extractvalue … , 0`:

  $ ./lab.exe --emit-llvm o.swift | grep -E 'alloca \{|extractvalue' | head -3
    %t0 = alloca { i64, i64 }
    %t1 = alloca { i64, i64 }
    %t10 = extractvalue { i64, i64 } %t9, 0
