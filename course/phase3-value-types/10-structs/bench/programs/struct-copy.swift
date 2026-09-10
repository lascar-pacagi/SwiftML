struct Six {
  var a: Int
  var b: Int
  var c: Int
  var d: Int
  var e: Int
  var f: Int
}

func rotateAndAdd(_ value: Six, _ step: Int) -> Six {
  let first = value.b + step % 7
  return Six(a: first, b: value.c, c: value.d, d: value.e, e: value.f, f: value.a)
}

var value = Six(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6)
for step in 0 ..< 50000000 {
  value = rotateAndAdd(value, step)
}
print(value.a + value.b + value.c + value.d + value.e + value.f)
