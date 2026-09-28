The instruction table in `gen_binop`. Every operand here is a literal, so the only lines in
these functions are the binops themselves: nothing else in `gen_instr` is reached. (Every
function still starts with `gen_allocas`, so write that hole first.)

Int arithmetic is one instruction per operator, and division and remainder are the SIGNED
ones, `sdiv` and `srem`: `-7 / 2` is `-3` in Swift, which `udiv` would get wrong. Both run
their divisor through the given zero guard first.

  $ printf '9 + 4\n9 - 4\n9 * 4\n9 / 4\n9 %% 4\n' > ar.swift
  $ ./lab.exe --emit-llvm-instrs ar.swift | sed -n '/define i32 @main/,$p'
  define i32 @main() {
  bb0:
    %t0 = add i64 9, 4
    %t1 = sub i64 9, 4
    %t2 = mul i64 9, 4
    %dz11 = call i64 @swiftml.divz(i64 4)
    %t3 = sdiv i64 9, %dz11
    %dz14 = call i64 @swiftml.remz(i64 4)
    %t4 = srem i64 9, %dz14
  }
  

Int comparisons are `icmp` with a SIGNED predicate (`slt`, not `ult`: `-1 < 0` must be true),
and produce an `i1`.

  $ printf '1 == 1\n1 != 2\n1 < 2\n1 <= 2\n2 > 1\n2 >= 1\n' > cmp.swift
  $ ./lab.exe --emit-llvm-instrs cmp.swift | grep -oE "icmp [a-z]+ i64"
  icmp eq i64
  icmp ne i64
  icmp slt i64
  icmp sle i64
  icmp sgt i64
  icmp sge i64

Double arithmetic is the `f` family: `fadd`, `fsub`, `fmul`, `fdiv`, with no zero guard —
dividing a Double by zero is not a trap in Swift, it gives an infinity.

  $ printf '9.0 + 4.0\n9.0 - 4.0\n9.0 * 4.0\n9.0 / 4.0\n' > dar.swift
  $ ./lab.exe --emit-llvm-instrs dar.swift | sed -n '/define i32 @main/,$p' | \
  > grep -oE "f(add|sub|mul|div) double|divz"
  fadd double
  fsub double
  fmul double
  fdiv double

Double comparisons are `fcmp`, ORDERED (`o…`: false if either side is NaN) for everything
except `!=`, which is UNORDERED (`une`: true if either side is NaN), so that `nan != nan` is
true as Swift requires.

  $ printf '9.0 == 4.0\n9.0 != 4.0\n9.0 < 4.0\n9.0 <= 4.0\n9.0 > 4.0\n9.0 >= 4.0\n' > dcmp.swift
  $ ./lab.exe --emit-llvm-instrs dcmp.swift | grep -oE "fcmp [a-z]+ double"
  fcmp oeq double
  fcmp une double
  fcmp olt double
  fcmp ole double
  fcmp ogt double
  fcmp oge double

`==` and `!=` on Bool compare the two `i1`s with `icmp`.

  $ printf 'true == false\ntrue != false\n' > bcmp.swift
  $ ./lab.exe --emit-llvm-instrs bcmp.swift | grep -oE "icmp [a-z]+ i1"
  icmp eq i1
  icmp ne i1
