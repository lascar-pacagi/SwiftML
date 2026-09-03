The token stream, through `./lab.exe --emit-tokens` — built from THIS directory's lexer, so it is
your `next` that is being run, not the phase binary. RED until `TODO(01-lexer)` is written.

The goldens below were produced by running the answer key; they are the spec, not a recording
of your output. If `dune promote` ever looks tempting, the test is telling you something.

`print(1 + 2)` lexes to eight tokens, ending in `newline` then `eof`.

  $ printf 'print(1 + 2)\n' > p.swift
  $ ./lab.exe --emit-tokens p.swift
  ident(print)
  (
  int(1)
  +
  int(2)
  )
  newline
  eof

Every operator and punctuation mark is its own token kind.
All of `+ - * / % =` and `( ) ,` in one line, plus keywords, identifiers and a multi-digit int:

  $ printf 'let x = (1 + 2 - 3 * 4 / 5 %% 6), y\n' > ops.swift
  $ ./lab.exe --emit-tokens ops.swift
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

`lets`, `varx`, `_let` and `let1` are identifiers, not keywords plus a tail.
Maximal munch: a keyword matches only as a WHOLE word, and a number or identifier is one token
however long it runs:

  $ printf 'lets lett varx _let let1 let var\n' > kw.swift
  $ ./lab.exe --emit-tokens kw.swift
  ident(lets)
  ident(lett)
  ident(varx)
  ident(_let)
  ident(let1)
  let
  var
  newline
  eof

`x1`, `_y2` and `z_3` are single identifiers, and a tab is whitespace.

  $ printf 'x1\t_y2  z_3 100200\n' > id.swift
  $ ./lab.exe --emit-tokens id.swift
  ident(x1)
  ident(_y2)
  ident(z_3)
  int(100200)
  newline
  eof

A comment is dropped but its line's newline is kept.
A comment-only first line still yields its line break; block comments NEST (a non-nesting
scanner mis-lexes the `b */` tail); and `//` runs to the end of the line:

  $ printf '// only a comment\n1 /* a /* nested */ b */ + 2 // tail\n' > c.swift
  $ ./lab.exe --emit-tokens c.swift
  newline
  int(1)
  +
  int(2)
  newline
  eof

A file with no trailing newline ends in `eof` with no `newline` before it.
(`-` is its own token either way — unary vs binary is the parser's job, not the lexer's.)

  $ printf 'print(-5)' > noeol.swift
  $ ./lab.exe --emit-tokens noeol.swift
  ident(print)
  (
  -
  int(5)
  )
  eof

`/**/`, `/*/ */`, `/* a **/` and `/*/**/*/` are all complete comments.
The last is the interesting one — two openers, two closers, nested — where C would already
have stopped at the first `*/`. swiftc accepts every form below:

  $ printf '/**/1\n/*/ */ 2\n/* a **/ 3\n/*/**/*/ 4\n/* // x */ 5\n// /* x\n6\n' > shapes.swift
  $ ./lab.exe --emit-tokens shapes.swift
  int(1)
  newline
  int(2)
  newline
  int(3)
  newline
  int(4)
  newline
  int(5)
  newline
  newline
  int(6)
  newline
  eof

An unclosed `/*` is reported at end of input, with swiftc's wording, exit 1.
The lexer REPORTS rather than dies (`diag::lex_unterminated_block_comment`) — and `/*/*/` is
unterminated in Swift, since nesting makes it two openers and one closer.

  $ printf 'let x = 1\n/*/\n' > unterm.swift
  $ ./lab.exe --emit-tokens unterm.swift 2>&1 | grep 'error:'
  3:1: error: unterminated '/*' comment
  $ ./lab.exe --emit-tokens unterm.swift > /dev/null 2>&1; echo "exit=$?"
  exit=1

(Filtered to `error:` on purpose: §6 exercise 2 adds two `note:` lines to this same
diagnostic, and a base-behaviour golden should not break when you do an exercise the
course invites you to do.)

A byte outside the alphabet is reported, dropped, and lexing continues.
Because the lexer RECOVERS, one run reports every bad character rather than only the first:

  $ printf 'let x = `1 + `2\n' > stray.swift
  $ ./lab.exe --emit-tokens stray.swift
  1:9: error: invalid character in source file
  1:14: error: invalid character in source file
  [1]
