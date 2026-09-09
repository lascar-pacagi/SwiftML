TODO(09) gen_instr — one LLVM line per SIL instruction, read through the test-only
`--emit-llvm-instrs` mode. It stops before each block's terminator, so these cases can turn green
while `gen_term` is still untouched.

Literals emit NO line: a SIL `integer_literal` becomes an LLVM *operand*. Here `1` and `true`
appear directly in stores, with no LLVM instruction defining them first.

  $ printf 'let one = 1\nlet yes = true\n' > lit.swift
  $ ./lab.exe --emit-llvm-instrs lit.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    %t0 = alloca i64
    %t1 = alloca i1
    store i64 1, ptr %t0
    store i1 1, ptr %t1
  }
  

A variable is an `alloca`, a write is a `store`, a read is a `load` — SIL's memory model maps
straight across, which is why IRGen is this short.

  $ printf 'let x = 1\nx\n' > mem.swift
  $ ./lab.exe --emit-llvm-instrs mem.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    %t0 = alloca i64
    store i64 1, ptr %t0
    %t1 = load i64, ptr %t0
  }
  

Every `alloca` belongs in the ENTRY block, even for a `let` declared inside a loop body: stack
space is only released when the function returns, so an alloca in a loop grows the stack every
trip. The given `gen_allocas` does this for you, and the SIL `Alloc_stack` case emits nothing.

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  let d = i * 2\n  s = s + d\n}\nprint(s)\n' > hoist.swift
  $ ./lab.exe --emit-llvm-instrs hoist.swift | sed -n '/^bb0:/,/^bb1:/p' | grep -c "alloca" || true
  3
  $ ./lab.exe --emit-llvm-instrs hoist.swift | sed -n '/^bb1:/,$p' | grep -c "alloca" || true
  0

Arithmetic is TYPED: the SIL `binop` carries its operand type, and each pairing picks one LLVM
mnemonic — signed division and remainder for `Int`, not the unsigned ones.

  $ cat > ar.swift <<'EOF'
  > 9 + 4
  > 9 - 4
  > 9 * 4
  > 9 / 4
  > 9 % 4
  > EOF
  $ ./lab.exe --emit-llvm-instrs ar.swift | grep -oE "(add|sub|mul|sdiv|srem) i64"
  add i64
  sub i64
  mul i64
  sdiv i64
  srem i64

Comparisons are `icmp` with a signed predicate, and produce an `i1`.

  $ printf '1 == 1\n1 != 2\n1 < 2\n1 <= 2\n2 > 1\n2 >= 1\n' > cmp.swift
  $ ./lab.exe --emit-llvm-instrs cmp.swift | grep -oE "icmp [a-z]+ i64"
  icmp eq i64
  icmp ne i64
  icmp slt i64
  icmp sle i64
  icmp sgt i64
  icmp sge i64

Unary minus has no LLVM opcode of its own on integers: it is a subtraction from zero.

  $ printf 'let n = 7\n-n\n' > neg.swift
  $ ./lab.exe --emit-llvm-instrs neg.swift | grep "sub i64"
    %t2 = sub i64 0, %t1

Double stack slots, stores, and loads keep their `double` type.

  $ printf 'let d = 1.5\nd\n' > dmem.swift
  $ ./lab.exe --emit-llvm-instrs dmem.swift | grep -E 'alloca double|store double|load double'
    %t0 = alloca double
    store double 0x3FF8000000000000, ptr %t0
    %t1 = load double, ptr %t0

Double arithmetic, negation, and comparisons use LLVM's floating-point instruction families.

  $ cat > dbl.swift <<'EOF'
  > let a = 9.0
  > let b = 4.0
  > -a
  > a + b
  > a - b
  > a * b
  > a / b
  > a == b
  > a != b
  > a < b
  > a <= b
  > a > b
  > a >= b
  > EOF
  $ ./lab.exe --emit-llvm-instrs dbl.swift | \
  > grep -oE 'fneg double|f(add|sub|mul|div) double|fcmp [a-z]+ double'
  fneg double
  fadd double
  fsub double
  fmul double
  fdiv double
  fcmp oeq double
  fcmp une double
  fcmp olt double
  fcmp ole double
  fcmp ogt double
  fcmp oge double

A `function_ref` emits no line either — it names the callee — and the `apply` becomes the
`call`. Every argument keeps its own type, and a `Void` function is called as `call void`.

  $ cat > call.swift <<'EOF'
  > func add(_ a: Int, _ b: Int) -> Int { return a + b }
  > func choose(_ flag: Bool, _ n: Int) -> Int {
  >   if flag { return n } else { return 0 }
  > }
  > func sink(_ n: Int) {}
  > add(1, 2)
  > choose(true, 4)
  > sink(3)
  > EOF
  $ ./lab.exe --emit-llvm-instrs call.swift | grep -E "call (void|i64) @"
    %t0 = call i64 @add(i64 1, i64 2)
    %t1 = call i64 @choose(i1 1, i64 4)
    call void @sink(i64 3)

`print` is the one builtin, and it lowers by type: an `Int` goes to printf directly, a `Bool`
first `select`s between the two string constants in the preamble.

  $ printf 'print(1)\nprint(true)\n' > pr.swift
  $ ./lab.exe --emit-llvm-instrs pr.swift | grep -E "printf|select"
  declare i32 @printf(ptr, ...)
    call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 1)
    %t0 = select i1 1, ptr @.btrue, ptr @.bfalse
    call i32 (ptr, ...) @printf(ptr @.fmt_str, ptr %t0)
