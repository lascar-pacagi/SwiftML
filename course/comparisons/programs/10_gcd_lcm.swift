// Euclid's GCD (recursive) and LCM.
func gcd(_ a: Int, _ b: Int) -> Int {
  if b == 0 { return a }
  return gcd(b, a % b)
}
func lcm(_ a: Int, _ b: Int) -> Int { return a / gcd(a, b) * b }
print(gcd(1071, 462))
print(gcd(48, 18))
print(lcm(4, 6))
print(lcm(21, 6))
print(gcd(17, 5))
