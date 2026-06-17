
// Conway's Game of Life on a flat WxH [Int] grid (1 = alive). Print population each generation.
func neighbors(_ g: [Int], _ w: Int, _ h: Int, _ r: Int, _ c: Int) -> Int {
  var count = 0
  var dr = -1
  while dr <= 1 {
    var dc = -1
    while dc <= 1 {
      if dr != 0 || dc != 0 {
        let nr = r + dr
        let nc = c + dc
        if nr >= 0 && nr < h && nc >= 0 && nc < w {
          if g[nr * w + nc] == 1 { count = count + 1 }
        }
      }
      dc = dc + 1
    }
    dr = dr + 1
  }
  return count
}
func stepLife(_ g: [Int], _ w: Int, _ h: Int) -> [Int] {
  var ng: [Int] = []
  var i = 0
  while i < w * h { ng.append(0); i = i + 1 }
  var r = 0
  while r < h {
    var c = 0
    while c < w {
      let n = neighbors(g, w, h, r, c)
      let alive = g[r * w + c]
      if alive == 1 && (n == 2 || n == 3) { ng[r * w + c] = 1 }
      if alive == 0 && n == 3 { ng[r * w + c] = 1 }
      c = c + 1
    }
    r = r + 1
  }
  return ng
}
func pop(_ g: [Int]) -> Int {
  var s = 0
  var i = 0
  while i < g.count { s = s + g[i]; i = i + 1 }
  return s
}
// a glider on a 6x6 grid
var grid = [0,1,0,0,0,0, 0,0,1,0,0,0, 1,1,1,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0]
var gen = 0
while gen < 8 {
  print(pop(grid))
  grid = stepLife(grid, 6, 6)
  gen = gen + 1
}
