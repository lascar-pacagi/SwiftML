Constant folding now reaches comparisons and bools, and CFG simplification deletes a branch
taken on a constant. RED until the TODO(17) holes (fold_binop + simplify_cfg) are filled.

A comparison folds to a bool:

  $ printf 'print(3 < 5)\n' > b.swift
  $ ./lab.exe --sil-opt b.swift | grep -oE 'integer_literal \$Bool, true'
  integer_literal $Bool, true

A branch on a constant condition is folded, and the dead `else` block disappears:

  $ printf 'if 10 > 3 { print(1) } else { print(2) }\n' > i.swift
  $ ./lab.exe --sil-opt i.swift | grep -c 'cond_br' || true
  0
  $ ./lab.exe --sil-opt i.swift | grep -oE 'integer_literal \$Int, 2' || true
  $ ./lab.exe build i.swift -O -o i && ./i
  1

`-O` preserves behavior — a constant-heavy program and a real loop both still match swiftc:

  $ printf 'let x = 6\nprint(x * x - (2 + 3))\n' > c.swift
  $ ./lab.exe build c.swift -O -o c && ./c
  31

  $ cat > s.swift <<'EOF'
  > var s = 0
  > for i in 0 ..< 10 { if i > 4 { s = s + i } }
  > print(s)
  > EOF
  $ ./lab.exe build s.swift -O -o s && ./s
  35
