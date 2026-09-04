TODO(09) gen_term — the four terminators. SIL blocks and LLVM blocks are the same idea, so
`br`, `cond_br`, `return` and `unreachable` map one to one; the only wrinkle is `@main`, which
LLVM gives an `i32` result even though the SIL function returns `$()`.

An unconditional `br bbN` becomes `br label %bbN`: here the entry falls into the loop header
and the body branches back to it.

  $ printf 'var n = 0\nwhile n < 3 {\n  n = n + 1\n}\nprint(n)\n' > w.swift
  $ ./lab.exe --emit-llvm w.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    %t0 = alloca i64
    store i64 0, ptr %t0
    br label %bb1
  bb1:
    %t1 = load i64, ptr %t0
    %t2 = icmp slt i64 %t1, 3
    br i1 %t2, label %bb2, label %bb3
  bb2:
    %t3 = load i64, ptr %t0
    %t4 = add i64 %t3, 1
    store i64 %t4, ptr %t0
    br label %bb1
  bb3:
    %t5 = load i64, ptr %t0
    call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 %t5)
    ret i32 0
  }
  

A `cond_br` becomes LLVM's two-target `br i1`, with the condition as an `i1` operand.

  $ printf 'let x = 5\nif x < 0 {\n  print(0)\n} else {\n  print(1)\n}\n' > i.swift
  $ ./lab.exe --emit-llvm i.swift | grep -E "br i1|br label"
    br i1 %t2, label %bb1, label %bb3
    br label %bb2
    br label %bb2

`return %v` becomes `ret <type> <operand>`, typed by the FUNCTION's return type, and a bare
`return` in a `Void` function is `ret void`.

  $ printf 'func id(_ x: Int) -> Int {\n  return x\n}\nfunc yes() -> Bool {\n  return true\n}\nfunc shout(_ n: Int) {\n  print(n)\n}\nshout(id(1))\nprint(yes())\n' > r.swift
  $ ./lab.exe --emit-llvm r.swift | grep -E "^  ret"
    ret i64 %t1
    ret i1 1
    ret void
    ret i32 0

`@main` is the exception: the SIL function returns `$()`, but the C entry point returns an
`i32`, so a valueless return there is `ret i32 0` — the process's exit code.

  $ printf 'print(1)\n' > m.swift
  $ ./lab.exe --emit-llvm m.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 1)
    ret i32 0
  }
  

An `unreachable` SIL block stays `unreachable` in LLVM — it is a real instruction, and the
merge block of an `if` whose arms both returned is where it shows up.

  $ printf 'func pick(_ c: Bool) -> Int {\n  if c {\n    return 1\n  } else {\n    return 2\n  }\n}\nprint(pick(true))\n' > p.swift
  $ ./lab.exe --emit-llvm p.swift | sed -n '/define i64 @pick/,/^}/p'
  define i64 @pick(i1 %arg0) {
  bb0:
    %t0 = alloca i1
    store i1 %arg0, ptr %t0
    %t1 = load i1, ptr %t0
    br i1 %t1, label %bb1, label %bb3
  bb1:
    ret i64 1
  bb2:
    unreachable
  bb3:
    ret i64 2
  }

The IR has to be well-formed, not merely printable: `clang` is the judge, and `build` runs it.

  $ ./lab.exe build p.swift -o p && ./p
  1
