TODO(12b)/TODO(12c) switch syntax — patterns and the arm list. `--emit-ast` stops before Sema,
so these say nothing about whether the cases exist on the enum.

A case pattern names an enum case, optionally binding its associated values; `_` discards one.

  $ printf 'switch s {\ncase .rect(let w, _):\nprint(w)\ncase .dot:\nprint(0)\n}\n' > pat.swift
  $ ./lab.exe --emit-ast pat.swift
  (switch s (case .rect(let w,_) ((print w))) (case .dot ((print 0))))

An Int literal is a pattern too, and may be negative.

  $ printf 'switch n {\ncase 1:\nprint(1)\ncase -2:\nprint(2)\ndefault:\nprint(0)\n}\n' > int.swift
  $ ./lab.exe --emit-ast int.swift
  (switch n (case 1 ((print 1))) (case -2 ((print 2))) (default ((print 0))))

An arm body runs to the next `case`, `default` or the closing brace — it is not brace-delimited.

  $ printf 'switch n {\ncase 0:\nlet a = 1\nprint(a)\ndefault:\nprint(9)\n}\n' > body.swift
  $ ./lab.exe --emit-ast body.swift
  (switch n (case 0 ((let a 1) (print a))) (default ((print 9))))

A pattern that is neither `.case` nor a literal is reported, and parsing continues.

  $ printf 'switch n {\ncase x:\nprint(1)\n}\n' > bad.swift
  $ ./lab.exe --emit-ast bad.swift 2>&1 | head -3
  2:6: error: expected a 'case' pattern
  case x:
       ^

Anything that is not an arm is reported, and the parser advances past it rather than spinning.

  $ printf 'switch n {\nnonsense\ncase 0:\nprint(1)\n}\n' > junk.swift
  $ ./lab.exe --emit-ast junk.swift 2>&1 | head -3
  2:1: error: expected 'case' or 'default'
  nonsense
  ^
