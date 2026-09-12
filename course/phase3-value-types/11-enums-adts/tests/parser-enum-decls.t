TODO(11b) enum declarations — `parse_enum` records the name, optional raw type, and cases
in source order. Each case retains its ordered associated-value type names.

A raw-value enum may put several payload-free cases on one line.

  $ printf 'enum Direction: Int { case north, east, south, west }\n' > direction.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast direction.swift
  (enum Direction :Int (north east south west))

Cases on separate lines may carry zero, one, or several associated-value types.

  $ cat > command.swift <<'EOF'
  > enum Command {
  >   case stop
  >   case move(Int, Bool)
  >   case wait(Int)
  > }
  > EOF
  $ python3 timeout.py 2 ./lab.exe --emit-ast command.swift
  (enum Command (stop move(Int,Bool) wait(Int)))

An enum declaration without a name reports at its opening brace.

  $ printf 'enum { case a }\n' > bad-name.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-name.swift 2>&1 | head -1
  1:6: error: expected an enum name

A colon after the enum name requires a written raw type.

  $ printf 'enum E: { case a }\n' > bad-raw-type.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-raw-type.swift 2>&1 | head -1
  1:9: error: expected a raw type

The enum name must be followed by its opening brace.

  $ printf 'enum E case a }\n' > bad-open.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-open.swift 2>&1 | head -1
  1:8: error: expected '{'

Only `case` introduces a declaration inside an enum body.

  $ printf 'enum E { value }\n' > bad-member.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-member.swift 2>&1 | head -1
  1:10: error: expected a 'case' declaration

Each `case` keyword must be followed by a case name.

  $ printf 'enum E { case (Int) }\n' > bad-case-name.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-case-name.swift 2>&1 | head -1
  1:15: error: expected a case name

An associated-value list cannot be empty in this subset.

  $ printf 'enum E { case value() }\n' > bad-payload-type.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-payload-type.swift 2>&1 | head -1
  1:21: error: expected an associated-value type

An associated-value list requires its closing parenthesis.

  $ printf 'enum E { case value(Int }\n' > bad-payload-close.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-payload-close.swift 2>&1 | head -1
  1:25: error: expected ')'

Two case declarations require a newline or semicolon between them.

  $ printf 'enum E { case a case b }\n' > bad-separator.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-separator.swift 2>&1 | head -1
  1:17: error: expected newline or end of declaration

An enum that reaches end of input without `}` reports the missing delimiter.

  $ printf 'enum E { case a' > bad-close.swift
  $ python3 timeout.py 2 ./lab.exe --emit-ast bad-close.swift 2>&1 | head -1
  1:16: error: expected '}'
