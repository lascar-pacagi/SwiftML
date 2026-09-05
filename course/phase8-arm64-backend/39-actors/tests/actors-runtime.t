GREEN before you start: an actor IS a class. The parser routes `actor X { … }` through the class
path, and SILGen and IRGen never learn the difference — same object header, same vtable, same
ARC. So the runtime half of this concept works before you write a line, and this file says what
the hole is NOT about. Read it first.

A Bank actor's state survives across awaited calls exactly as a class's does, and matches swiftc.

  $ cat > a.swift <<'SWIFT'
  > actor Bank {
  >   var balance: Int
  >   init() { balance = 100 }
  >   func deposit(_ n: Int) { balance = balance + n }
  >   func withdraw(_ n: Int) -> Bool {
  >     if balance >= n { balance = balance - n; return true }
  >     return false
  >   }
  >   func report() -> Int { return balance }
  > }
  > let b = Bank()
  > await b.deposit(50)
  > let ok = await b.withdraw(30)
  > print(ok)
  > print(await b.report())
  > SWIFT
  $ ./lab.exe build a.swift -o a && ./a
  true
  120
  $ swiftc -Onone a.swift -o a_sw && ./a_sw
  true
  120

The SIL confirms there is no actor machinery at all: the methods are ordinary class methods
dispatched through a vtable, and the `sil_vtable` is the one concept 25 emits.

  $ ./lab.exe --emit-sil a.swift | grep -E -c 'sil_vtable Bank' || true
  1
  $ ./lab.exe --emit-sil a.swift | grep -c 'actor' || true
  0

Reference semantics too — two bindings to one actor see one state.

  $ cat > share.swift <<'SWIFT'
  > actor Box {
  >   var v: Int
  >   init() { v = 0 }
  >   func put(_ n: Int) { v = n }
  >   func get() -> Int { return v }
  > }
  > let x = Box()
  > let y = x
  > await x.put(41)
  > print(await y.get())
  > SWIFT
  $ ./lab.exe build share.swift -o share && ./share
  41
  $ swiftc -Onone share.swift -o share_sw && ./share_sw
  41
