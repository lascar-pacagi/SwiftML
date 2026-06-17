// Protocols + a generic function: polymorphic area.
protocol Shape {
  func area() -> Int
}
struct Square: Shape {
  var side: Int
  func area() -> Int { return side * side }
}
struct Rectangle: Shape {
  var w: Int
  var h: Int
  func area() -> Int { return w * h }
}
struct Triangle: Shape {
  var base: Int
  var height: Int
  func area() -> Int { return base * height / 2 }
}
func describe<T: Shape>(_ s: T) -> Int {
  return s.area()
}
print(describe(Square(side: 5)))
print(describe(Rectangle(w: 3, h: 7)))
print(describe(Triangle(base: 6, height: 4)))
// existential heterogeneous dispatch
let shapes: [Int] = [describe(Square(side: 2)), describe(Rectangle(w: 2, h: 3)), describe(Triangle(base: 4, height: 4))]
var total = 0
var i = 0
while i < shapes.count { total = total + shapes[i]; i = i + 1 }
print(total)
