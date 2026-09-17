SILGen lowers the TYPE-CHECKED tree, and this file pins what that buys. Sema recorded the type of
every node, so nothing here re-derives one — see PLAN.md §0.1 for the version that did.

An integer literal that adopted Double is BORN a Double. The whole left-hand tree is float
literals, generated once, in source order, with nothing abandoned in the block. Before the typed
tree, this arm generated the left operand as Int, discovered the right was Double, generated the
right, then RE-generated the left — and the dead Int copy stayed, and still executed at -Onone:

  $ printf 'let d = 1.5\nprint((1 + 2 * 3) * d)\n' > s1.swift
  $ ./lab.exe --emit-sil s1.swift
  sil @main() -> $() {
  bb0:
    %0 = float_literal $Double, 1.5
    %1 = alloc_stack $Double  // d
    store %0 to %1
    %3 = float_literal $Double, 1
    %4 = float_literal $Double, 2
    %5 = float_literal $Double, 3
    %6 = binop "*" %4, %5 $Double
    %7 = binop "+" %3, %6 $Double
    %8 = load %1 $Double
    %9 = binop "*" %7, %8 $Double
    %10 = apply @print(%9)
    return
  }

Not one `integer_literal` appears above, which is the point: the coercion happened in Sema and was
written down, so SILGen never had to notice it. Counting is the durable form of that claim:

  $ ./lab.exe --emit-sil s1.swift | grep -c integer_literal || true
  0

A trapping literal tree on the left is the case that used to change behaviour between -Onone and
-O: the abandoned Int copy divided by zero, while the live Double copy produced inf. Generated
once, there is only one division, and it is the Double one:

  $ printf 'let d = 1.5\nprint((1 / 0) * d)\n' > s2.swift
  $ ./lab.exe --emit-sil s2.swift | grep 'binop "/"'
    %5 = binop "/" %3, %4 $Double
