
// Protocols + structs + a class hierarchy + generics + dynamic dispatch, all together.
protocol Shape {
  func area() -> Int
  func scaled(_ k: Int) -> Int
}
struct Square: Shape {
  var side: Int
  func area() -> Int { return side * side }
  func scaled(_ k: Int) -> Int { return side * k * side * k }
}
struct Rect: Shape {
  var w: Int
  var h: Int
  func area() -> Int { return w * h }
  func scaled(_ k: Int) -> Int { return w * k * h * k }
}
class Animal {
  var legs: Int
  init(_ l: Int) { legs = l }
  func sound() -> Int { return 0 }
  func describe() -> Int { return legs * 100 + sound() }
}
class Dog: Animal {
  init() { super.init(4) }
  override func sound() -> Int { return 7 }
}
class Bird: Animal {
  init() { super.init(2) }
  override func sound() -> Int { return 3 }
}
func totalArea<T: Shape>(_ s: T) -> Int { return s.area() }
print(totalArea(Square(side: 5)))
print(totalArea(Rect(w: 3, h: 7)))
let sq = Square(side: 4)
print(sq.scaled(2))
let d = Dog()
let b = Bird()
print(d.describe())
print(b.describe())
// dynamic dispatch through a superclass-typed variable
var a: Animal = d
print(a.describe())
a = b
print(a.describe())
