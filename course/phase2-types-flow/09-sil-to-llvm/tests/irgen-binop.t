The instruction table, `binop_instruction`, on its own: `--binop-table <type>` asks it for every
operator that exists at that operand type and prints the answers. No program is compiled, so
no other hole is reached.

Int arithmetic is one instruction per operator, and division and remainder are the SIGNED
ones, `sdiv` and `srem`: `-7 / 2` is `-3` in Swift, which `udiv` would get wrong.

  $ ./lab.exe --binop-table Int | sed -n '1,5p'
  +   add i64
  -   sub i64
  *   mul i64
  /   sdiv i64
  %   srem i64

Int comparisons are `icmp` with a SIGNED predicate (`slt`, not `ult`: `-1 < 0` must be true);
the operand type is `i64` even though the result is a Bool.

  $ ./lab.exe --binop-table Int | sed -n '6,11p'
  ==  icmp eq i64
  !=  icmp ne i64
  <   icmp slt i64
  <=  icmp sle i64
  >   icmp sgt i64
  >=  icmp sge i64

Double arithmetic is the `f` family: `fadd`, `fsub`, `fmul`, `fdiv`.

  $ ./lab.exe --binop-table Double | sed -n '1,4p'
  +   fadd double
  -   fsub double
  *   fmul double
  /   fdiv double

Double comparisons are `fcmp`, ORDERED (`o…`: false if either side is NaN) for everything
except `!=`, which is UNORDERED (`une`: true if either side is NaN), so that `nan != nan` is
true as Swift requires.

  $ ./lab.exe --binop-table Double | sed -n '5,10p'
  ==  fcmp oeq double
  !=  fcmp une double
  <   fcmp olt double
  <=  fcmp ole double
  >   fcmp ogt double
  >=  fcmp oge double

`==` and `!=` on Bool compare the two `i1`s with `icmp`.

  $ ./lab.exe --binop-table Bool
  ==  icmp eq i1
  !=  icmp ne i1
