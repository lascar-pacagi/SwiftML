This cram test checks the token stream `swiftml --emit-tokens` produces.

It is RED until you implement `lexer.ml : next` (in the concept directory). Once your output is correct,
record/refresh the golden output below with:  dune promote
(run from course/, after `dune build @phase1-minimal/01-lexer/runtest`).

Lex a small arithmetic program:

  $ printf 'print(1 + 2)\n' > p.swift
  $ swiftml --emit-tokens p.swift
  ident(print)
  (
  int(1)
  +
  int(2)
  )
  newline
  eof

Every operator and punctuation token has a distinct kind — exercise all of them
(`+ - * / % =` and `( ) ,`), plus keywords, identifiers, and a multi-digit int:

  $ printf 'let x = (1 + 2 - 3 * 4 / 5 %% 6), y\n' > ops.swift
  $ swiftml --emit-tokens ops.swift
  let
  ident(x)
  =
  (
  int(1)
  +
  int(2)
  -
  int(3)
  *
  int(4)
  /
  int(5)
  %
  int(6)
  )
  ,
  ident(y)
  newline
  eof

Maximal munch: a multi-digit number is one token; an identifier is one token; and a
keyword is matched **only as a whole word** — `lets`/`varx`/`_let`/`let1` are identifiers,
not `let`/`var` followed by something:

  $ printf 'lets lett varx _let let1 let var\n' > kw.swift
  $ swiftml --emit-tokens kw.swift
  ident(lets)
  ident(lett)
  ident(varx)
  ident(_let)
  ident(let1)
  let
  var
  newline
  eof

Identifier shapes (leading `_`, trailing/embedded digits) and a tab as whitespace:

  $ printf 'x1\t_y2  z_3 100200\n' > id.swift
  $ swiftml --emit-tokens id.swift
  ident(x1)
  ident(_y2)
  ident(z_3)
  int(100200)
  newline
  eof

Comments are trivia but newlines are significant. A comment-only first line still yields
its line break; block comments `/* … */` **nest** (a non-nesting scanner would mis-lex the
`b */` tail), and `//` runs to end of line:

  $ printf '// only a comment\n1 /* a /* nested */ b */ + 2 // tail\n' > c.swift
  $ swiftml --emit-tokens c.swift
  newline
  int(1)
  +
  int(2)
  newline
  eof

End of input without a trailing newline emits no final `newline`, just `eof` (and `-` is
its own token — unary vs binary is the parser's job, not the lexer's):

  $ printf 'print(-5)' > noeol.swift
  $ swiftml --emit-tokens noeol.swift
  ident(print)
  (
  -
  int(5)
  )
  eof
