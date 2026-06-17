// Phase 1 corpus: let/var bindings, variable references, reassignment of var.
let a = 6
let b = 7
print(a * b)            // 42
var c = a + b           // 13
c = c * 2               // var may be reassigned
print(c)                // 26
