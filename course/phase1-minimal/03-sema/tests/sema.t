Checks name resolution and the trivial type rules. Uses `--typecheck` (lex → parse → sema,
no codegen — like `swiftc -typecheck`), so this exercises Sema *directly* and in isolation.

RED until you implement `sema.ml : check` (in the concept directory).

A valid program type-checks with no diagnostics and exits 0 (note it reassigns a `var` and
references earlier bindings — none of that may be falsely rejected):

  $ printf 'let a = 2\nvar c = a + 1\nc = c * a\nprint(c)\n' > ok.swift
  $ swiftml --typecheck ok.swift >out.txt 2>err.txt; echo "exit=$?"
  exit=0
  $ test -s err.txt && cat err.txt || echo "no diagnostics"
  no diagnostics

Using an undeclared variable is rejected, with swiftc's wording, and a nonzero exit:

  $ printf 'print(y)\n' > u1.swift
  $ swiftml --typecheck u1.swift 2>&1 | grep -o "cannot find 'y' in scope" || true
  cannot find 'y' in scope
  $ swiftml --typecheck u1.swift >/dev/null 2>&1; echo "exit=$?"
  exit=1

Assigning to an undeclared name is the same "in scope" error:

  $ printf 'x = 5\n' > u2.swift
  $ swiftml --typecheck u2.swift 2>&1 | grep -o "cannot find 'x' in scope" || true
  cannot find 'x' in scope

A name is in scope only *after* its declaration — using it in its own initializer fails:

  $ printf 'let a = a\n' > u3.swift
  $ swiftml --typecheck u3.swift 2>&1 | grep -o "cannot find 'a' in scope" || true
  cannot find 'a' in scope

Assigning to a `let` constant is rejected (a `var` in the same spot would be fine):

  $ printf 'let k = 1\nk = 2\n' > c1.swift
  $ swiftml --typecheck c1.swift 2>&1 | grep -o "cannot assign to value: 'k' is a 'let' constant" || true
  cannot assign to value: 'k' is a 'let' constant
  $ swiftml --typecheck c1.swift >/dev/null 2>&1; echo "exit=$?"
  exit=1

Several problems in one file are ALL reported, in source order, each at its own
line:column — one run tells you everything it can see:

  $ printf 'print(p + q)\nlet a = 1\nfoo(a)\n' > multi.swift
  $ swiftml --typecheck multi.swift
  1:7: error: cannot find 'p' in scope
  1:11: error: cannot find 'q' in scope
  3:1: error: cannot find 'foo' in scope
  [1]

A call to anything but print(_:) is an unknown name, and its arguments are still
checked (both messages, exactly as swiftc reports them):

  $ printf 'bar(z)\n' > call.swift
  $ swiftml --typecheck call.swift
  1:1: error: cannot find 'bar' in scope
  1:5: error: cannot find 'z' in scope
  [1]

print(_:) takes exactly one argument, and a well-formed call is silent:

  $ printf 'print(1, 2)\n' > arity.swift
  $ swiftml --typecheck arity.swift
  1:1: error: print(_:) expects exactly one argument
  [1]
  $ printf 'let a = 2\nprint(-(a * (a + 1)) %% 7)\n' > ok2.swift
  $ swiftml --typecheck ok2.swift; echo "exit=$?"
  exit=0
