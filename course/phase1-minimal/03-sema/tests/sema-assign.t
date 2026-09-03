Assignment, through `--typecheck`: the target must exist and must be a `var`. Only `error:`
lines are compared, so the §6 note exercise ("change 'let' to 'var'…") may be done or not.

`k = 2` on a `let` is "cannot assign to value: 'k' is a 'let' constant".
Reported at the assignment, exit 1:

  $ printf 'let k = 1\nk = 2\n' > c1.swift
  $ ./lab.exe --typecheck c1.swift 2>&1 | grep 'error:'
  2:1: error: cannot assign to value: 'k' is a 'let' constant
  $ ./lab.exe --typecheck c1.swift >/dev/null 2>&1; echo "exit=$?"
  exit=1

The same two lines with `var` are accepted.
Mutability is the only difference:

  $ printf 'var k = 1\nk = 2\n' > c2.swift
  $ ./lab.exe --typecheck c2.swift; echo "exit=$?"
  exit=0

`v = q` with `q` unknown reports `q`: the assigned expression is checked too:

  $ printf 'var v = 1\nv = q\n' > c3.swift
  $ ./lab.exe --typecheck c3.swift
  2:5: error: cannot find 'q' in scope
  [1]

Reading a `let` is always fine; only writing one is an error:

  $ printf 'let k = 5\nvar v = k\nv = v + k\nprint(v * k)\n' > c4.swift
  $ ./lab.exe --typecheck c4.swift; echo "exit=$?"
  exit=0
