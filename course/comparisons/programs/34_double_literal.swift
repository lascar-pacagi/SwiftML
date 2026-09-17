// An integer literal beside a Double is a DOUBLE literal, not an Int that gets converted.
// Sema's unification decides that; SILGen has to generate the literal side AT Double, or IRGen
// emits `fmul double %d, 2` and clang refuses it. The literal can sit on either side.
// Results are compared rather than printed: our `print` of a Double uses %g, swiftc prints 3.0.

let d = 1.5

print(d * 2 == 3.0)
print(2 * d == 3.0)
print(d + 2 == 3.5)
print(2 + d == 3.5)
print(d - 2 == -0.5)
print(2 - d == 0.5)
print(d / 2 == 0.75)
print(2 / d > 1.3)

// the whole literal TREE flexes, not just a leaf
print(d * (2 + 1) == 4.5)
print((1 + 1) * d == 3.0)
print(-2 * d == -3.0)

func scale(_ x: Double) -> Double { return x * 2 }
print(scale(d) == 3.0)
