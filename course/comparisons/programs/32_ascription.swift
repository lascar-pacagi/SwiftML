// `e as T` coercion + Double values. Prints Bools and Ints, never a raw Double: our `%g`
// formatting prints 1.0 as "1" where Swift prints "1.0" (a documented divergence).
func half(_ x: Double) -> Double { return x / 2.0 }
func isClose(_ a: Double, _ b: Double) -> Bool { return a - b < 0.001 && b - a < 0.001 }

let one = 1 as Double
let three: Double = 1 + 2
let sum = (1 + 2) as Double
let neg = -3 as Double

print(one > 0.5)
print(isClose(three, 3.0))
print(isClose(sum, 3.0))
print(isClose(neg, 0.0 - 3.0))
print(isClose(half(one), 0.5))

// `as` binds looser than arithmetic, tighter than a comparison
print(isClose(1 + 2 as Double, 3.0))
print(1 < 2 as Int)

// in a loop, and through a function boundary. NOTE `i as Double` would be REJECTED here:
// `i` is an Int *variable*, and the coercion is for literals — the same rule as annotations.
var acc = 0.0
var i = 0
while i < 5 {
  acc = acc + (2 as Double)
  i = i + 1
}
print(isClose(acc, 10.0))

// Int ascription is a no-op that still type-checks
let n = 7 as Int
print(n * 6)

// mixed literal trees flex whole
let big: Double = 2 * 3 + 4
print(isClose(big, 10.0))
print(isClose(half(big), 5.0))
