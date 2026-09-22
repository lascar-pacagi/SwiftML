Termination, from the outside. `tests/test_scale.ml` argues that `infer` and `check_expr`
cannot recurse forever and that checking is linear, and it measures both — but alcotest has
no per-case timeout, so a checker that truly LOOPS hangs it instead of failing it. This runs
the same shape under `timeout`, which turns a hang into a red test in 10 seconds.

`1 as Double as Double as …` is the shape to use: `as` is the one form where `infer` calls
`check_expr`, which falls back to `infer`, so a 5000-deep chain of them bounces between the
two judgments 5000 times. If either ever passes its OWN argument across, this never returns.

  $ python3 -c "print('print(1' + ' as Double'*5000 + ')')" > deep.swift
  $ timeout 10 ./lab.exe --typecheck deep.swift; echo "exit=$?"
  exit=0
