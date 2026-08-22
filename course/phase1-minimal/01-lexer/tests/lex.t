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

Comment shapes the scanner has to get exactly right. `/*/*/` is the interesting one:
Swift's block comments nest, so that's *two* openers and one closer — unterminated —
where C would read it as one finished comment. The forms below are all legal
(`swiftc -typecheck` accepts every one of them):

  $ printf '/**/1\n/*/ */ 2\n/* a **/ 3\n/*/**/*/ 4\n/* // x */ 5\n// /* x\n6\n' > shapes.swift
  $ swiftml --emit-tokens shapes.swift
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

A block comment that is never closed is an error, not a silent stop — and the lexer
REPORTS it rather than dying: same wording and same position as `swiftc`
(`diag::lex_unterminated_block_comment`, at end of input), on stderr, exit 1.

  $ printf 'let x = 1\n/*/\n' > unterm.swift
  $ swiftml --emit-tokens unterm.swift 2>&1 | grep 'error:'
  3:1: error: unterminated '/*' comment
  $ swiftml --emit-tokens unterm.swift > /dev/null 2>&1; echo "exit=$?"
  exit=1

(Filtered to `error:` on purpose: §6 exercise 2 adds two `note:` lines to this same
diagnostic, and a base-behaviour golden should not break when you do an exercise the
course invites you to do.)

Same for a byte outside the alphabet — and because the lexer RECOVERS (drops the byte and
keeps scanning), one run reports every bad character instead of only the first:

  $ printf 'let x = `1 + `2\n' > stray.swift
  $ swiftml --emit-tokens stray.swift
  1:9: error: invalid character in source file
  1:14: error: invalid character in source file
  [1]
