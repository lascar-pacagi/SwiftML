TODO(37) — what the directives become. `clang -g` hands the `.s` to the assembler, which turns
the `.loc` stream into a real **DWARF line table** in the object file: a mapping from machine
address to source line. That table is the artifact; the directives were only how we asked for it.

`dwarfdump` reads it back. Every line that has code appears, in increasing address order — 2 and
3 inside `square`, 5 through 8 in `main`.

  $ cat > x.swift <<'SWIFT'
  > func square(_ n: Int) -> Int {
  >   let r = n * n
  >   return r
  > }
  > let a = 6
  > let b = square(a)
  > print(b)
  > print(a + b)
  > SWIFT
  $ ./lab.exe build x.swift --native -o x && ./x
  36
  42
  $ dwarfdump --debug-line x.o | grep -E '^0x[0-9a-f]+ ' | awk '{print $2}' | sort -u | tr '\n' ' '
  2 3 5 6 7 8 

Each row is a statement boundary — the rows a debugger would offer as breakpoint locations.

  $ dwarfdump --debug-line x.o | grep -cE '^0x[0-9a-f]+ .* is_stmt'
  7

macOS keeps the DWARF in the OBJECT file and leaves only a debug map in the executable, so the
driver assembles to a kept `<out>.o` and links that. `clang -g file.s -o exe` would delete the
temporary object and the map would point at nothing.

  $ test -f x.o && echo "the object file is kept"
  the object file is kept

HONEST SCOPE: the line table is real and complete, and `.debug_info` is EMPTY. That section holds
the DIEs — a compile unit, a subprogram per function, a variable per local — and without at least
a compile-unit DIE `lldb` will not bind a source breakpoint, and `print r` has nothing to read.
So the automated check here is `dwarfdump`, not a debugger session; emitting the DIEs is
exercise 2.

  $ dwarfdump --debug-info x.o | grep -c 'DW_TAG_compile_unit' || true
  0
