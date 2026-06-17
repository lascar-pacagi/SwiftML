
// Recursive-descent evaluator over an [Int] token stream with precedence + parentheses.
// Tokens: >=0 is a number literal; -1='+', -2='-', -3='*', -4='/', -5='(', -6=')'.
// A global-ish position is threaded by returning (value, nextPos) packed: we return value and read
// position from a 1-element [Int] cursor passed by value-then-rebuilt (functional threading).
func parseExpr(_ t: [Int], _ posIn: Int) -> [Int] {
  // returns [value, nextPos]
  var r = parseTerm(t, posIn)
  var val = r[0]
  var pos = r[1]
  while pos < t.count && (t[pos] == -1 || t[pos] == -2) {
    let op = t[pos]
    r = parseTerm(t, pos + 1)
    if op == -1 { val = val + r[0] } else { val = val - r[0] }
    pos = r[1]
  }
  var out: [Int] = []
  out.append(val)
  out.append(pos)
  return out
}
func parseTerm(_ t: [Int], _ posIn: Int) -> [Int] {
  var r = parseAtom(t, posIn)
  var val = r[0]
  var pos = r[1]
  while pos < t.count && (t[pos] == -3 || t[pos] == -4) {
    let op = t[pos]
    r = parseAtom(t, pos + 1)
    if op == -3 { val = val * r[0] } else { val = val / r[0] }
    pos = r[1]
  }
  var out: [Int] = []
  out.append(val)
  out.append(pos)
  return out
}
func parseAtom(_ t: [Int], _ posIn: Int) -> [Int] {
  if t[posIn] == -5 {
    let r = parseExpr(t, posIn + 1)
    var out: [Int] = []
    out.append(r[0])
    out.append(r[1] + 1)   // skip ')'
    return out
  }
  var out: [Int] = []
  out.append(t[posIn])
  out.append(posIn + 1)
  return out
}
func eval(_ t: [Int]) -> Int {
  let r = parseExpr(t, 0)
  return r[0]
}
// 2 + 3 * 4 => 14
print(eval([2, -1, 3, -3, 4]))
// (2 + 3) * 4 => 20
print(eval([-5, 2, -1, 3, -6, -3, 4]))
// 100 - 2 * (3 + 4) => 86
print(eval([100, -2, 2, -3, -5, 3, -1, 4, -6]))
