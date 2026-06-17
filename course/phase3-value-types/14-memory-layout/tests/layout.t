Memory layout: size/stride/alignment + field offsets, matching swiftc's MemoryLayout exactly
for structs of scalars. RED until the TODO(14) holes (the padding walk + the field offsets).

Natural alignment and padding — `{Int; Bool}` is size 9 but `{Bool; Int}` is size 16:

  $ cat > s.swift <<'SWIFT'
  > struct P { var x: Int; var y: Int }
  > struct Mixed { var b: Bool; var i: Int }
  > struct Mixed2 { var i: Int; var b: Bool }
  > struct Three { var a: Bool; var b: Bool; var c: Int }
  > SWIFT
  $ ./lab.exe --emit-layout s.swift
  Int: size=8 stride=8 align=8
  Bool: size=1 stride=1 align=1
  Double: size=8 stride=8 align=8
  P: size=16 stride=16 align=8
    .x offset=0
    .y offset=8
  Mixed: size=16 stride=16 align=8
    .b offset=0
    .i offset=8
  Mixed2: size=9 stride=16 align=8
    .i offset=0
    .b offset=8
  Three: size=16 stride=16 align=8
    .a offset=0
    .b offset=1
    .c offset=8

Nested structs compose — a struct field aligns and sizes by its own layout:

  $ cat > n.swift <<'SWIFT'
  > struct Inner { var a: Bool; var b: Int }
  > struct Outer { var flag: Bool; var inner: Inner }
  > SWIFT
  $ ./lab.exe --emit-layout n.swift | grep -A3 'Outer:'
  Outer: size=24 stride=24 align=8
    .flag offset=0
    .inner offset=8
