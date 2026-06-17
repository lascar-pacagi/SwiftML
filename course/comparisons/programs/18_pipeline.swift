// Functional pipeline: map / filter / reduce + a captured variable.
let nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let squares = nums.map({ (x: Int) -> Int in x * x })
let evens = squares.filter({ (x: Int) -> Bool in x % 2 == 0 })
let sum = evens.reduce(0, { (acc: Int, x: Int) -> Int in acc + x })
print(squares.count)
print(evens.count)
print(sum)
let factor = 3
let scaled = nums.map({ (x: Int) -> Int in x * factor })
print(scaled.reduce(0, { (a: Int, b: Int) -> Int in a + b }))
let sumOfCubes = nums.reduce(0, { (a: Int, x: Int) -> Int in a + x * x * x })
print(sumOfCubes)
