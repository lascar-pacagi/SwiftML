TODO(09) gen_instr — one LLVM line per SIL instruction, read through the test-only
`--emit-llvm-instrs` mode. It stops before each block's terminator, so these cases can turn green
while `gen_term` is still untouched. Every function starts with `gen_allocas`, so they read TODO
until that hole is written.

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
  

A `binop` becomes one line: the instruction from `binop_instruction`, then the two operands. An
Int `/` or `%` first runs its divisor through the given zero guard, and divides by what the
guard returns; a Double `/` has no guard, since dividing a Double by zero gives an infinity.

  $ printf '9 + 4\n9 / 4\n9 %% 4\n9.0 / 4.0\n' > ar.swift
  $ ./lab.exe --emit-llvm-instrs ar.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    %t0 = add i64 9, 4
    %dz5 = call i64 @swiftml.divz(i64 4)
    %t1 = sdiv i64 9, %dz5
    %dz8 = call i64 @swiftml.remz(i64 4)
    %t2 = srem i64 9, %dz8
    %t3 = fdiv double 0x4022000000000000, 0x4010000000000000
  }
  

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

Double negation is `fneg`, LLVM's one-operand floating-point instruction — not a subtraction
from zero, which gives `+0.0` for `-(0.0)` where Swift gives `-0.0`.

  $ printf 'let a = 9.0\n-a\n' > dneg.swift
  $ ./lab.exe --emit-llvm-instrs dneg.swift | grep "fneg"
    %t2 = fneg double %t1

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
