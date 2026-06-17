
// Levenshtein edit distance between two [Int] sequences via a flat (m+1)x(n+1) DP table.
func editDistance(_ a: [Int], _ b: [Int]) -> Int {
  let m = a.count
  let n = b.count
  var dp: [Int] = []
  var i = 0
  while i < (m + 1) * (n + 1) { dp.append(0); i = i + 1 }
  var r = 0
  while r <= m { dp[r * (n + 1)] = r; r = r + 1 }
  var c = 0
  while c <= n { dp[c] = c; c = c + 1 }
  r = 1
  while r <= m {
    c = 1
    while c <= n {
      if a[r - 1] == b[c - 1] {
        dp[r * (n + 1) + c] = dp[(r - 1) * (n + 1) + (c - 1)]
      } else {
        var best = dp[(r - 1) * (n + 1) + c]
        let ins = dp[r * (n + 1) + (c - 1)]
        let sub = dp[(r - 1) * (n + 1) + (c - 1)]
        if ins < best { best = ins }
        if sub < best { best = sub }
        dp[r * (n + 1) + c] = best + 1
      }
      c = c + 1
    }
    r = r + 1
  }
  return dp[m * (n + 1) + n]
}
// "kitten" vs "sitting" as char codes => 3
print(editDistance([107,105,116,116,101,110], [115,105,116,116,105,110,103]))
// "flaw" vs "lawn" => 2
print(editDistance([102,108,97,119], [108,97,119,110]))
// equal
print(editDistance([1,2,3], [1,2,3]))
