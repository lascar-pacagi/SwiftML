TODO(09) gen_term — the four terminators. SIL blocks and LLVM blocks are the same idea, so
`br`, `cond_br`, `return` and `unreachable` map one to one; the only wrinkle is `@main`, which
LLVM gives an `i32` result even though the SIL function returns `$()`.

An unconditional `br bbN` becomes `br label %bbN`: here the entry falls into the loop header
and the body branches back to it.

  $ printf 'var n = 0\nwhile n < 3 {\n  n = n + 1\n}\nprint(n)\n' > w.swift
  $ ./lab.exe --emit-llvm-terms br w.swift | grep -oE 'br label %?bb[0-9]+'
  br label %bb1
  br label %bb1

A `cond_br` becomes LLVM's two-target `br i1`, with the condition as an `i1` operand.

  $ printf 'let x = 5\nif x < 0 {\n  print(0)\n} else {\n  print(1)\n}\n' > i.swift
  $ ./lab.exe --emit-llvm-terms cond-br i.swift | grep -oE 'br i1 %[^,]+, label %?bb[0-9]+, label %?bb[0-9]+'
  br i1 %t2, label %bb1, label %bb3

`return %v` becomes `ret <type> <operand>`, typed by the FUNCTION's return type. Selecting only
value-carrying returns keeps `main`'s still-unfinished valueless return out of this check.

  $ printf 'func id(_ x: Int) -> Int {\n  return x\n}\nfunc yes() -> Bool {\n  return true\n}\nprint(id(1))\nprint(yes())\n' > rv.swift
  $ ./lab.exe --emit-llvm-terms return-value rv.swift | grep -oE 'ret (i64|i1) (%t[0-9]+|[01])'
  ret i64 %t1
  ret i1 1

A bare `return` in a `Void` function becomes `ret void`.

  $ printf 'func shout(_ n: Int) {\n  print(n)\n}\nshout(1)\n' > rn.swift
  $ ./lab.exe --emit-llvm-terms return-none rn.swift | grep -o 'ret void'
  ret void

`@main` is the exception: the SIL function returns `$()`, but the C entry point returns an
`i32`, so a valueless return there is `ret i32 0` — the process's exit code.

  $ printf 'print(1)\n' > m.swift
  $ ./lab.exe --emit-llvm-terms return-none m.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    call i32 (ptr, ...) @printf(ptr @.fmt_int, i64 1)
    ret i32 0
  }
  

An `unreachable` SIL block stays `unreachable` in LLVM — it is a real instruction, and the
merge block of an `if` whose arms both returned is where it shows up.

  $ printf 'func pick(_ c: Bool) -> Int {\n  if c {\n    return 1\n  } else {\n    return 2\n  }\n}\nprint(pick(true))\n' > p.swift
  $ ./lab.exe --emit-llvm-terms unreachable p.swift | grep -o 'unreachable'
  unreachable

The IR has to be well-formed, not merely printable: `clang` is the judge, and `build` runs it.

  $ ./lab.exe build p.swift -o p && ./p
  1
