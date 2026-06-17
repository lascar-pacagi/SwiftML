// Ternary operator stress: min/max/sign/clamp, deeply-nested classification, ternary in recursion.
func mymin(_ a: Int, _ b: Int) -> Int { return a < b ? a : b }
func mymax(_ a: Int, _ b: Int) -> Int { return a > b ? a : b }
func sign(_ x: Int) -> Int { return x > 0 ? 1 : (x < 0 ? 0 - 1 : 0) }
func clamp(_ x: Int, _ lo: Int, _ hi: Int) -> Int { return x < lo ? lo : (x > hi ? hi : x) }
func gcd(_ a: Int, _ b: Int) -> Int { return b == 0 ? a : gcd(b, a % b) }
let data = [3, -7, 0, 12, -1, 8, -20, 5]
var mn = data[0]
var mx = data[0]
var i = 0
while i < data.count {
  mn = mymin(mn, data[i])
  mx = mymax(mx, data[i])
  i = i + 1
}
print(mn)
print(mx)
print(sign(-5))
print(sign(0))
print(sign(99))
print(clamp(150, 0, 100))
print(clamp(-3, 0, 100))
print(clamp(50, 0, 100))
print(gcd(48, 36))
// nested-ternary FizzBuzz code (0/1/2/4), folded into one number
var f = 1
var out = 0
while f <= 15 {
  let v = f % 15 == 0 ? 4 : (f % 3 == 0 ? 1 : (f % 5 == 0 ? 2 : 0))
  out = out * 10 + v
  f = f + 1
}
print(out % 1000000)
