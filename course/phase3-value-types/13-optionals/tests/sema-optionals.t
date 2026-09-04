The optional rules of sema — GIVEN code, so this file is green from the start; it is here so
the diagnostics the front end owes you are on record before you lower anything. `--typecheck`
stops after sema: exit 0 and silence is "accepted", exit 1 with `line:col: error: …` is not.

A well-formed optional program — annotation, `nil`, `if let`, `??`, `!`, `== nil` — is accepted:

  $ cat > ok.swift <<'EOF'
  > func f(_ n: Int) -> Int? {
  >   if n < 0 { return nil }
  >   return n * 2
  > }
  > let a: Int? = 5
  > let b: Int? = nil
  > if let v = a { print(v) }
  > print(b ?? 99)
  > print(a!)
  > print(a == nil)
  > print(f(3) ?? 0)
  > EOF
  $ ./lab.exe --typecheck ok.swift

`nil` has no type of its own: it is only legal where a `T?` is expected, and `let n: Int = nil`
is where that shows:

  $ cat > barenil.swift <<'EOF'
  > let n: Int = nil
  > EOF
  $ ./lab.exe --typecheck barenil.swift
  1:14: error: 'nil' cannot be used with a non-optional type 'Int'
  [1]

`!` unwraps an optional and nothing else — a plain `Int` has nothing to unwrap:

  $ cat > bang.swift <<'EOF'
  > let n = 5
  > print(n!)
  > EOF
  $ ./lab.exe --typecheck bang.swift
  2:7: error: cannot force-unwrap a non-optional value of type 'Int'
  [1]

`if let` binds an optional's payload, so its right-hand side must BE an optional; the binding
it would have made does not happen, so `v` is unknown in the body:

  $ cat > iflet.swift <<'EOF'
  > if let v = 3 { print(v) }
  > EOF
  $ ./lab.exe --typecheck iflet.swift
  1:1: error: initializer for conditional binding must have Optional type, not 'Int'
  1:22: error: cannot find 'v' in scope
  [1]

An `Int?` is NOT an `Int`: it does not convert on its own, and it does not do arithmetic. This
is the point of the type — you have to say what happens when it is `nil`:

  $ cat > noconv.swift <<'EOF'
  > let a: Int? = 5
  > let n: Int = a
  > print(a + 1)
  > EOF
  $ ./lab.exe --typecheck noconv.swift
  2:14: error: cannot convert value of type 'Int?' to specified type 'Int'
  3:7: error: binary operator '+' cannot be applied to operands of type 'Int?' and 'Int'
  [1]

`??` has to produce ONE type: the default must match what the optional wraps:

  $ cat > coalty.swift <<'EOF'
  > let a: Int? = 5
  > let b: Bool = a ?? false
  > EOF
  $ ./lab.exe --typecheck coalty.swift
  2:20: error: cannot convert value of type 'Bool' to specified type 'Int'
  2:15: error: cannot convert value of type 'Int' to specified type 'Bool'
  [1]

The wrap is CHECKED, not blind: `Int?` accepts an `Int`, not a `String`, and `x = true` on an
`Int?` var is caught at the assignment:

  $ cat > wrapty.swift <<'EOF'
  > let a: Int? = "s"
  > var x: Int? = 5
  > x = true
  > EOF
  $ ./lab.exe --typecheck wrapty.swift
  1:15: error: cannot convert value of type 'String' to specified type 'Int'
  3:5: error: cannot convert value of type 'Bool' to specified type 'Int'
  [1]

A `-> Int?` function still checks what it returns — `return true` is not an `Int?`:

  $ cat > retty.swift <<'EOF'
  > func f() -> Int? {
  >   return true
  > }
  > EOF
  $ ./lab.exe --typecheck retty.swift
  2:10: error: cannot convert value of type 'Bool' to specified type 'Int'
  [1]

`== nil` is the one comparison an optional gets; two optionals cannot be compared with each
other (swiftc synthesizes that from `Equatable`, we do not — §2), and a non-optional cannot be
compared with `nil`:

  $ cat > cmp.swift <<'EOF'
  > let a: Int? = 5
  > let b: Int? = 6
  > print(a == b)
  > EOF
  $ ./lab.exe --typecheck cmp.swift
  3:7: error: binary operator '==' cannot be applied to two 'Int?' operands
  [1]

`print` of an optional is refused up front (swiftc prints `Optional(5)` through reflection — a
documented divergence, §2) instead of crashing IRGen:

  $ cat > printopt.swift <<'EOF'
  > let a: Int? = 5
  > print(a)
  > EOF
  $ ./lab.exe --typecheck printopt.swift
  2:7: error: cannot print a value of type 'Int?' (only Int, Double, Bool and String)
  [1]
