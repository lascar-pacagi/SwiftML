Debug info: source locations threaded into a DWARF-lite line table, so lldb can step by line.
RED until the TODO(37) hole (emitting `.loc` directives when the source line changes).

The asm names the source file (`.file`) and marks each statement's line (`.loc`) — and the program
still runs and matches swiftc:

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
  $ ./lab.exe --emit-asm x.swift | grep -E '^\t\.file'
  	.file	1 "x.swift"
  $ ./lab.exe --emit-asm x.swift | grep -E '^\t\.loc' | head
  	.loc	1 2 0
  	.loc	1 3 0
  	.loc	1 5 0
  	.loc	1 6 0
  	.loc	1 7 0
  	.loc	1 8 0
  $ ./lab.exe build x.swift --native -o x && ./x
  36
  42

The built object carries a real DWARF line table mapping machine addresses to source lines (built
by the assembler from our `.loc` directives) — this is what lets `lldb` set breakpoints by line:

  $ dwarfdump --debug-line x.o | grep -E '^0x[0-9a-f]+ ' | awk '{print $2}' | sort -u | tr '\n' ' '
  2 3 5 6 7 8 

The line table is sound — every address maps to a line that actually has code (2,3 in the function;
5,6,7,8 in main), in increasing address order:

  $ dwarfdump --debug-line x.o | grep -cE '^0x[0-9a-f]+ .* is_stmt'
  7
