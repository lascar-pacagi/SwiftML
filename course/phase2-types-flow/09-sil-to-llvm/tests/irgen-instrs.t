TODO(09) gen_instr — one LLVM line per SIL instruction, read through `--emit-llvm`. The two
holes are coupled: `--emit-llvm` prints a whole module or nothing, and `gen_instr` is what runs
first, so fill it first and expect `irgen-terms.t` to go green in the same sitting.

Literals emit NO line: a SIL `integer_literal` becomes an LLVM *operand*, so `1` and `true`
appear inside the instructions that use them and cost nothing of their own.

  $ printf 'print(1)\nprint(true)\n' > lit.swift
  $ ./lab.exe --emit-llvm lit.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 1)
    %t0 = select i1 1, ptr @.btrue, ptr @.bfalse
    call i32 (ptr, ...) @printf(ptr @.fmt_str, ptr %t0)
    ret i32 0
  }
  

A variable is an `alloca`, a write is a `store`, a read is a `load` — SIL's memory model maps
straight across, which is why IRGen is this short.

  $ printf 'let x = 1\nvar n = x + 2\nn = n * 3\nprint(n)\n' > mem.swift
  $ ./lab.exe --emit-llvm mem.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    %t0 = alloca i64
    %t1 = alloca i64
    store i64 1, ptr %t0
    %t2 = load i64, ptr %t0
    %t3 = add i64 %t2, 2
    store i64 %t3, ptr %t1
    %t4 = load i64, ptr %t1
    %t5 = mul i64 %t4, 3
    store i64 %t5, ptr %t1
    %t6 = load i64, ptr %t1
    call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 %t6)
    ret i32 0
  }
  

Every `alloca` belongs in the ENTRY block, even for a `let` declared inside a loop body: stack
space is only released when the function returns, so an alloca in a loop grows the stack every
trip. The given `gen_allocas` does this for you, and the SIL `Alloc_stack` case emits nothing.

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  let d = i * 2\n  s = s + d\n}\nprint(s)\n' > hoist.swift
  $ ./lab.exe --emit-llvm hoist.swift | sed -n '/^bb0:/,/^bb1:/p' | grep -c "alloca" || true
  3
  $ ./lab.exe --emit-llvm hoist.swift | sed -n '/^bb1:/,$p' | grep -c "alloca" || true
  0

Arithmetic is TYPED: the SIL `binop` carries its operand type, and each pairing picks one LLVM
mnemonic — signed division and remainder for `Int`, not the unsigned ones.

  $ cat > ar.swift <<'EOF'
  > print(9 + 4)
  > print(9 - 4)
  > print(9 * 4)
  > print(9 / 4)
  > print(9 % 4)
  > EOF
  $ ./lab.exe --emit-llvm ar.swift | grep -oE "(add|sub|mul|sdiv|srem) i64"
  add i64
  sub i64
  mul i64
  sdiv i64
  srem i64

Comparisons are `icmp` with a signed predicate, and produce an `i1`.

  $ printf 'print(1 == 1)\nprint(1 != 2)\nprint(1 < 2)\nprint(1 <= 2)\nprint(2 > 1)\nprint(2 >= 1)\n' > cmp.swift
  $ ./lab.exe --emit-llvm cmp.swift | grep -oE "icmp [a-z]+ i64"
  icmp eq i64
  icmp ne i64
  icmp slt i64
  icmp sle i64
  icmp sgt i64
  icmp sge i64

Unary minus has no LLVM opcode of its own on integers: it is a subtraction from zero.

  $ printf 'let n = 7\nprint(-n)\n' > neg.swift
  $ ./lab.exe --emit-llvm neg.swift | grep "sub i64"
    %t2 = sub i64 0, %t1

A `function_ref` emits no line either — it names the callee — and the `apply` becomes the
`call`, typed by the function's return type; a `Void` function is called as `call void`.

  $ printf 'func add(_ a: Int, _ b: Int) -> Int {\n  return a + b\n}\nfunc shout(_ n: Int) {\n  print(n)\n}\nshout(add(1, 2))\n' > call.swift
  $ ./lab.exe --emit-llvm call.swift | grep -E "call (void|i64) @"
    %t0 = call i64 @add(i64 1, i64 2)
    call void @shout(i64 %t0)

`print` is the one builtin, and it lowers by type: an `Int` goes to printf directly, a `Bool`
first `select`s between the two string constants in the preamble.

  $ printf 'print(1)\nprint(true)\n' > pr.swift
  $ ./lab.exe --emit-llvm pr.swift | grep -E "printf|select"
  declare i32 @printf(ptr, ...)
    call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 1)
    %t0 = select i1 1, ptr @.btrue, ptr @.bfalse
    call i32 (ptr, ...) @printf(ptr @.fmt_str, ptr %t0)
