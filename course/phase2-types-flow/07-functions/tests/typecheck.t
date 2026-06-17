End-to-end via `./lab.exe`: --emit-ast for functions, --typecheck for the rules.
RED until the lexer/parser/sema TODO(07) holes are filled.

A function declaration and a call parse into the AST:

  $ printf 'func add(_ a: Int, _ b: Int) -> Int {\n  return a + b\n}\nprint(add(1, 2))\n' > a.swift
  $ ./lab.exe --emit-ast a.swift
  (func add (a:Int b:Int) -> Int ((return (+ a b))))
  (print (add 1 2))

A recursive, well-typed program type-checks (exit 0). Recursion and the forward use of a
function both rely on collecting signatures before checking bodies:

  $ cat > ok.swift <<'EOF'
  > func fib(_ n: Int) -> Int {
  >   if n < 2 { return n }
  >   return fib(n - 1) + fib(n - 2)
  > }
  > print(fib(10))
  > EOF
  $ ./lab.exe --typecheck ok.swift >out.txt 2>err.txt; echo "exit=$?"
  exit=0
  $ test -s err.txt && cat err.txt || echo "no diagnostics"
  no diagnostics

Rejections with the matching diagnostic:

  $ printf 'func f() -> Int {\n  print(1)\n}\n' > b1.swift
  $ ./lab.exe --typecheck b1.swift 2>&1 | grep -o "missing return in function expected to return 'Int'" || true
  missing return in function expected to return 'Int'

  $ printf 'func f(_ x: Int) -> Int { return x }\nprint(f(1, 2))\n' > b2.swift
  $ ./lab.exe --typecheck b2.swift 2>&1 | grep -o "function 'f' expects 1 argument(s) but 2 given" || true
  function 'f' expects 1 argument(s) but 2 given

  $ printf 'return 1\n' > b3.swift
  $ ./lab.exe --typecheck b3.swift 2>&1 | grep -o "'return' invalid outside of a func" || true
  'return' invalid outside of a func
