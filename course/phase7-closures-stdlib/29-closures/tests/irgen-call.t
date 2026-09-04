TODO(29b) — the indirect call, in `irgen.ml`. A function value is the pair `{ code, ctx }`;
calling one takes the pair apart and calls the code with the context first. That is the whole
consumer side of the ABI.

A NAMED function used as a value needs no lifting, so this case reads 29b on its own: `dbl`
rides the convention through a thunk with a null context, and `g(50)` is the indirect call.

  $ cat > thin.swift <<'SWIFT'
  > func dbl(_ x: Int) -> Int { return x * 2 }
  > let g = dbl
  > print(g(50))
  > SWIFT
  $ ./lab.exe --emit-llvm thin.swift | grep -E 'extractvalue %thickfn|call i64 %'
    %t1 = extractvalue %thickfn %v3, 0
    %t2 = extractvalue %thickfn %v3, 1
    %v5 = call i64 %t1(ptr %t2, i64 50)

  $ ./lab.exe build thin.swift -o thin && ./thin
  100

With the lifting in place too, a closure call is the same three instructions — the context is
just no longer null:

  $ cat > mk.swift <<'SWIFT'
  > func makeAdder(_ n: Int) -> (Int) -> Int {
  >   return { (x: Int) -> Int in x + n }
  > }
  > let add7 = makeAdder(7)
  > let add9 = makeAdder(9)
  > print(add7(1))
  > print(add9(1))
  > SWIFT
  $ ./lab.exe build mk.swift -o mk && ./mk
  8
  10

  $ ./lab.exe build mk.swift -O -o mkO && ./mkO
  8
  10

A Void-returning call has no result to name, so it is a bare `call void` — and the lifted body,
whose single expression is itself of type `()`, returns nothing:

  $ cat > v.swift <<'SWIFT'
  > let show = { (x: Int) -> Void in print(x * 3) }
  > show(14)
  > SWIFT
  $ ./lab.exe --emit-llvm v.swift | grep 'call void %t'
    call void %t4(ptr %t5, i64 14)
  $ ./lab.exe --emit-llvm v.swift | sed -n '/define void @main\$clo0/,/^}/p' | tail -2
    ret void
  }
  $ ./lab.exe build v.swift -o v && ./v
  42
