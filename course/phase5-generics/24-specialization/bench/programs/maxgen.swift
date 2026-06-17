protocol Ord { func key() -> Int }
struct Item: Ord { var k: Int
  var pad: Int
  func key() -> Int { return k } }
func biggest<T: Ord>(_ a: T, _ b: T) -> T {
  if a.key() > b.key() { return a }
  return b
}
var best = Item(k: 0, pad: 0)
var seed = 12345
for _i in 0 ..< 8000000 {
  seed = (seed * 1103515245 + 12345) % 2147483648
  best = biggest(best, Item(k: seed % 100000, pad: seed))
}
print(best.k)
