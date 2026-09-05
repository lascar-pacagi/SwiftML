The type rules for `[Int]` and `String`, and the two places our subset is smaller than Swift
(given code, so this file is green from the start).

The buffer is a homogeneous store of machine words, so v0 is `[Int]` and nothing else. This is
the concept's stated scope, and its first exercise:

  $ cat > s.swift <<'SWIFT'
  > let names = ["a", "b"]
  > print(names.count)
  > SWIFT
  $ ./lab.exe --typecheck s.swift
  1:13: error: arrays of 'String' are not supported in this subset (only '[Int]'; element-generic buffers are this concept's exercise)
  [1]

A literal's elements must agree, and an empty one takes its element type from the annotation:

  $ cat > mix.swift <<'SWIFT'
  > let a: [Int] = [1, "x"]
  > SWIFT
  $ ./lab.exe --typecheck mix.swift
  1:20: error: cannot convert value of type 'String' to specified type 'Int'
  [1]

`append` MUTATES, so it needs a `var`. A `let` array is a constant value, not a constant handle
on a mutable buffer — swiftc says so in these words, and until this was checked, `a.append(3)`
on a `let` compiled and grew it:

  $ cat > la.swift <<'SWIFT'
  > let a = [1, 2]
  > a.append(3)
  > SWIFT
  $ ./lab.exe --typecheck la.swift
  2:1: error: cannot use mutating member on immutable value: 'a' is a 'let' constant
  [1]

The subscript write has always had the matching rule:

  $ cat > ls.swift <<'SWIFT'
  > let a = [1, 2]
  > a[0] = 5
  > SWIFT
  $ ./lab.exe --typecheck ls.swift
  2:4: error: cannot assign through subscript: 'a' is a 'let' constant
  [1]

An `Int` is not a collection, and `for-in` needs one:

  $ cat > sub.swift <<'SWIFT'
  > let a = [1, 2]
  > print(a[0][1])
  > SWIFT
  $ ./lab.exe --typecheck sub.swift
  2:7: error: value of type 'Int' has no subscripts
  [1]

  $ printf 'for x in 5 { print(x) }\n' > fi.swift
  $ ./lab.exe --typecheck fi.swift
  1:1: error: type 'Int' is not a sequence
  1:20: error: cannot find 'x' in scope
  [1]

Two divergences, in the restrictive direction, both because the back end has no aggregate
support: swiftc prints `[1, 2]` for an array and compares two arrays elementwise, and we refuse
both rather than emitting an `add i64 %ptr` that clang throws out.

  $ cat > pr.swift <<'SWIFT'
  > let a = [1, 2]
  > print(a)
  > SWIFT
  $ ./lab.exe --typecheck pr.swift
  2:7: error: cannot print a value of type '[Int]' (only Int, Double, Bool and String)
  [1]

  $ cat > eq.swift <<'SWIFT'
  > let a = [1, 2]
  > let b = [1, 2]
  > print(a == b)
  > SWIFT
  $ ./lab.exe --typecheck eq.swift
  3:7: error: binary operator '==' cannot be applied to two '[Int]' operands
  [1]

A `String` is a C string, byte-indexed and not subscriptable here; `count` is bytes, not
graphemes, which is a divergence on non-ASCII text and stated as one:

  $ cat > str.swift <<'SWIFT'
  > let s = "hi"
  > print(s[0])
  > SWIFT
  $ ./lab.exe --typecheck str.swift
  2:7: error: value of type 'String' has no subscripts
  [1]
