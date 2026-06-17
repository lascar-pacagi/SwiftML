
// Dijkstra shortest paths on an adjacency-matrix graph (flat [Int], 0 = no edge). INF sentinel.
func dijkstra(_ adj: [Int], _ n: Int, _ src: Int) -> [Int] {
  let INF = 1000000
  var dist: [Int] = []
  var done: [Int] = []
  var i = 0
  while i < n { dist.append(INF); done.append(0); i = i + 1 }
  dist[src] = 0
  var count = 0
  while count < n {
    // pick the unfinished vertex with the smallest dist
    var u = -1
    var best = INF
    var v = 0
    while v < n {
      if done[v] == 0 && dist[v] < best { best = dist[v]; u = v }
      v = v + 1
    }
    if u == -1 { count = n } else {
      done[u] = 1
      var w = 0
      while w < n {
        let e = adj[u * n + w]
        if e > 0 && dist[u] + e < dist[w] { dist[w] = dist[u] + e }
        w = w + 1
      }
      count = count + 1
    }
  }
  return dist
}
// 5-vertex graph
let adj = [0,4,0,0,8,  4,0,8,0,11,  0,8,0,7,0,  0,0,7,0,2,  8,11,0,2,0]
let d = dijkstra(adj, 5, 0)
var i = 0
while i < d.count { print(d[i]); i = i + 1 }
