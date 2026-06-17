// Run-length encoding over a byte sequence ([Int] of codes): produce (value,count) pairs flat.
func rle(_ data: [Int]) -> [Int] {
  var out: [Int] = []
  if data.count == 0 { return out }
  var prev = data[0]
  var count = 1
  var i = 1
  while i < data.count {
    if data[i] == prev { count = count + 1 } else { out.append(prev); out.append(count); prev = data[i]; count = 1 }
    i = i + 1
  }
  out.append(prev); out.append(count)
  return out
}
let data = [7, 7, 7, 3, 3, 9, 9, 9, 9, 1, 7, 7]
let encoded = rle(data)
var i = 0
while i < encoded.count { print(encoded[i]); i = i + 1 }
print(encoded.count / 2)   // number of runs
