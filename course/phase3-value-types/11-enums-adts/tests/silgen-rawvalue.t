TODO(11i) `.rawValue` lowering — an enum declared `: Int` reads its case index. Sema has already
decided the read is legal, so SILGen only emits the instruction that produces the index.
`--emit-sil` stops at this stage; the built program's OUTPUT is `irgen-enums.t`'s business.

A raw-value read is one instruction on the enum value, and its result is an `Int`.

  $ cat > raw.swift <<'EOF'
  > enum Dir: Int { case north, south, east }
  > print(Dir.east.rawValue)
  > EOF
  $ python3 timeout.py 2 ./lab.exe --emit-sil raw.swift | grep -A1 'enum #2'
    %0 = enum #2 () $Dir
    %1 = enum_tag %0

The value it reads is the whole enum, not a payload, so no extract or load stands between them.

  $ python3 timeout.py 2 ./lab.exe --emit-sil raw.swift | grep -c 'enum_tag'
  1
