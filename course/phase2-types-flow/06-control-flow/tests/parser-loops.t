Loops, through `--emit-ast`. Needs the control-flow arms of `parse_stmt` (`while`, `for … in
lo ..< hi`, `break`, `continue`) plus `parse_block` from the previous hole.

`while cond { body }`:

  $ printf 'var n = 0\nwhile n < 3 {\n  n = n + 1\n}\n' > w.swift
  $ ./lab.exe --emit-ast w.swift
  (var n 0)
  (while (< n 3) ((= n (+ n 1))))

`for i in 0 ..< n { body }` dumps as `(for i lo hi body)`; the bounds are expressions:

  $ printf 'let n = 3\nfor i in 0 ..< n + 1 {\n  print(i)\n}\n' > f.swift
  $ ./lab.exe --emit-ast f.swift
  (let n 3)
  (for i 0 (+ n 1) ((print i)))

`break` and `continue` are statements of their own:

  $ printf 'while true {\n  if true {\n    break\n  }\n  continue\n}\n' > bc.swift
  $ ./lab.exe --emit-ast bc.swift
  (while true ((if true (break)) continue))

Loops nest, and a body can hold every statement kind:

  $ printf 'var s = 0\nfor i in 0 ..< 3 {\n  var j = 0\n  while j < i {\n    s = s + j\n    j = j + 1\n  }\n}\n' > nest.swift
  $ ./lab.exe --emit-ast nest.swift
  (var s 0)
  (for i 0 3 ((var j 0) (while (< j i) ((= s (+ s j)) (= j (+ j 1))))))

`for i 0 ..< 3` without `in` is "expected 'in'", at the `0`:

  $ printf 'for i 0 ..< 3 {\n}\n' > e1.swift
  $ ./lab.exe --emit-ast e1.swift; echo "exit=$?"
  1:7: error: expected 'in'
  exit=1

`for i in 0 to 3` — no `..<` — is "expected '..<'" first; the rest of the line cascades:

  $ printf 'for i in 0 to 3 {\n}\n' > e2.swift
  $ ./lab.exe --emit-ast e2.swift 2>&1 | head -1
  1:12: error: expected '..<'
