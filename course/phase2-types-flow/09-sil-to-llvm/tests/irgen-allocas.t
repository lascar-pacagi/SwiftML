The allocas, before anything else: `--emit-llvm-allocas` drops every SIL instruction except
`alloc_stack` and prints no terminator, so what is left of each function is its blocks and the
lines `gen_allocas` wrote.

Every `alloca` belongs in the ENTRY block, even for a `let` declared inside a loop body: stack
space is only released when the function returns, so an alloca in a loop grows the stack every
trip. The loop's blocks are empty labels.

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  let d = i * 2\n  s = s + d\n}\nprint(s)\n' > hoist.swift
  $ ./lab.exe --emit-llvm-allocas hoist.swift | sed -n '/^define/,$p'
  define i32 @main() {
  bb0:
    %t0 = alloca i64
    %t1 = alloca i64
    %t2 = alloca i64
  bb1:
  bb2:
  bb3:
  bb4:
  }
  

The alloca of a slot carries the slot's LLVM type: `i64` for Int, `i1` for Bool, `double` for
Double, `ptr` for String.

  $ printf 'let n = 1\nlet b = true\nlet d = 1.5\nlet s = "hi"\n' > types.swift
  $ ./lab.exe --emit-llvm-allocas types.swift | grep alloca
    %t0 = alloca i64
    %t1 = alloca i1
    %t2 = alloca double
    %t3 = alloca ptr

Slots declared in both arms of an `if` all land at the top of `bb0`, in the order SILGen
created them.

  $ cat > arms.swift <<'EOF'
  > let x = 1
  > if x < 2 {
  >   let a = 10
  >   print(a)
  > } else {
  >   let b = true
  >   print(b)
  > }
  > EOF
  $ ./lab.exe --emit-llvm-allocas arms.swift | sed -n '/^define/,$p'
  define i32 @main() {
  bb0:
    %t0 = alloca i64
    %t1 = alloca i64
    %t2 = alloca i1
  bb1:
  bb2:
  bb3:
  }
  

Each function hoists its own slots into its OWN entry block, and a function with no local
variable gets no alloca at all.

  $ cat > funcs.swift <<'EOF'
  > func twice(_ n: Int) -> Int {
  >   let m = n * 2
  >   return m
  > }
  > func hello() {
  >   print(1)
  > }
  > let r = twice(4)
  > hello()
  > EOF
  $ ./lab.exe --emit-llvm-allocas funcs.swift | sed -n '/^define/,$p'
  define i64 @twice(i64 %arg0) {
  bb0:
    %t0 = alloca i64
    %t1 = alloca i64
  }
  
  define void @hello() {
  bb0:
  }
  
  define i32 @main() {
  bb0:
    %t0 = alloca i64
  }
  
