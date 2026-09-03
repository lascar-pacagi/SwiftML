End-to-end, the slot model: bindings, reads, and reassignment. A `var` must be ONE alloca
that later stores overwrite — a fresh slot per write, or a read that finds the first
value, prints something plausible and wrong.

`let a = 6; var c = a + 7; c = c * 2` prints 26: a read after a write sees the write:

  $ cat > v.swift <<'EOF'
  > let a = 6
  > var c = a + 7
  > c = c * 2
  > print(c)
  > EOF
  $ ./lab.exe build v.swift -o v && ./v
  26

`x = x + 4; x = x * x` from 1 prints 25, then `x - 5` is 20: each read sees the latest store:

  $ cat > w.swift <<'EOF'
  > var x = 1
  > x = x + 4
  > x = x * x
  > print(x)
  > let y = x - 5
  > print(y)
  > EOF
  $ ./lab.exe build w.swift -o w && ./w
  25
  20

Two vars reassigned in terms of each other: 25, 17, then `a % b + a / b` is 9:

  $ cat > many.swift <<'EOF'
  > var a = 3
  > var b = 4
  > a = a * a + b * b
  > b = a - b * 2
  > print(a)
  > print(b)
  > print(a % b + a / b)
  > EOF
  $ ./lab.exe build many.swift -o many && ./many
  25
  17
  9

Plain overwrites: 12, 42, 84, then a var written three times prints its LAST value, 3.
A compiler that keeps handing out a variable's first value prints 12, 12, 24, 1 here:

  $ cat > re.swift <<'EOF'
  > var x = 12
  > print(x)
  > x = 42
  > print(x)
  > x = x + x
  > print(x)
  > var y = 1
  > y = 2
  > y = 3
  > print(y)
  > EOF
  $ ./lab.exe build re.swift -o re && ./re
  12
  42
  84
  3

`--emit-llvm` shows the module itself: printf declared, `@main` defined and returning 0.
Checked on `re.swift`, whose two vars are both reassigned — so they need a slot in every
variant of this lowering, §6's exercises included:

  $ ./lab.exe --emit-llvm re.swift | grep -cE 'declare i32 @printf|define i32 @main|ret i32 0'
  3

Each reassigned var is ONE `alloca`, and every `store`/`load` of `x` names that same
register — 3 stores and 5 loads of it, 8 lines through one pointer:

  $ ./lab.exe --emit-llvm re.swift | grep -c 'alloca i64'
  2
  $ ./lab.exe --emit-llvm re.swift | grep -E 'store|load' | grep -oE 'ptr %[a-z0-9.]+' | sort | uniq -c | sort -rn | head -1 | awk '{print $1}'
  8
