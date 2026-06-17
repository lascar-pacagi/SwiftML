GVN / common-subexpression elimination keeps only one copy of a repeated computation. RED until
the TODO(18) holes (value_key + the dominance-scoped numbering) are filled.

`x * x + x * x` computes the product twice in raw SIL, once after GVN:

  $ printf 'func f(_ x: Int) -> Int { return x * x + x * x }\nprint(f(6))\n' > g.swift
  $ ./lab.exe --emit-sil g.swift | grep -c 'binop "\*"'
  2
  $ ./lab.exe --sil-opt g.swift | grep -c 'binop "\*"'
  1

`-O` preserves behavior — repeated subexpressions, including across a branch:

  $ ./lab.exe build g.swift -O -o g && ./g
  72

  $ cat > h.swift <<'EOF'
  > func h(_ n: Int) -> Int {
  >   if n * 2 > 10 { return n * 2 } else { return n * 2 + 1 }
  > }
  > print(h(7))
  > EOF
  $ ./lab.exe build h.swift -O -o h && ./h
  14

  $ cat > s.swift <<'EOF'
  > var s = 0
  > for i in 0 ..< 20 { s = s + i * i + i * i }
  > print(s)
  > EOF
  $ ./lab.exe build s.swift -O -o s && ./s
  4940

Two structs with identical fields but DIFFERENT types must not be merged (a once-shipped bug
produced ill-typed LLVM here — the -O build failed):

  $ cat > tt.swift <<'EOF'
  > struct A { var x: Int }
  > struct B { var x: Int }
  > func fb(_ b: B) -> Int { return b.x }
  > let a = A(x: 1)
  > print(a.x + fb(B(x: 1)))
  > EOF
  $ ./lab.exe build tt.swift -O -o tt && ./tt
  2
