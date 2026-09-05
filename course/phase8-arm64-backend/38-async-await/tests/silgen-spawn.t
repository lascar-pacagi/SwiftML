TODO(38) — `Task { … }`. The body becomes a lifted void function — a coroutine the executor will
run on its own stack — and `rt_async_spawn` enqueues it. Nothing new enters SIL: this is a lift
(concept 29's closure lifting) plus a runtime call.

Each `Task { }` lifts one function named after the enclosing one, and calls `rt_async_spawn`
once. Three tasks, three lifted functions, three spawns.

  $ cat > conc.swift <<'SWIFT'
  > func worker(_ id: Int) async {
  >   print(id * 10 + 1)
  >   await Task.yield()
  >   print(id * 10 + 2)
  >   await Task.yield()
  >   print(id * 10 + 3)
  > }
  > Task { await worker(1) }
  > Task { await worker(2) }
  > Task { await worker(3) }
  > print(0)
  > SWIFT
  $ ./lab.exe --emit-sil conc.swift | grep -c 'rt_async_spawn' || true
  3
  $ ./lab.exe --emit-sil conc.swift | grep -E -c '^sil @main\$task[0-9]' || true
  3

The lifted body is a plain void function taking the closure context, and the spawn hands the
runtime a closure value built from it.

  $ ./lab.exe --emit-sil conc.swift | grep -E '^sil @main\$task0'
  sil @main$task0(%0 : $$ctx) -> $() {
  $ ./lab.exe --emit-sil conc.swift | grep -c 'closure @main\$task' || true
  3

THE INTERLEAVING. Our executor is a SERIAL, deterministic FIFO: `rt_async_run` drains the ready
queue, each task runs until it yields, and a yielding task goes to the back. So three tasks with
two yields each interleave round by round, and `main`'s own `print(0)` comes first because the
queue is not drained until main ends. swiftc is NOT the oracle here — its default executor is
concurrent and this order is not guaranteed — so this golden is our documented semantics.

  $ ./lab.exe build conc.swift -o conc && ./conc
  0
  11
  21
  31
  12
  22
  32
  13
  23
  33

A task that never yields runs to completion before the next one starts — the same rule, with
one round.

  $ cat > noyield.swift <<'SWIFT'
  > func quick(_ id: Int) async {
  >   print(id)
  >   print(id * 100)
  > }
  > Task { await quick(1) }
  > Task { await quick(2) }
  > print(0)
  > SWIFT
  $ ./lab.exe build noyield.swift -o noyield && ./noyield
  0
  1
  100
  2
  200

A task spawned inside a function is lifted onto that function's name, and still runs when main
drains the queue — the queue is global, not scoped.

  $ cat > infn.swift <<'SWIFT'
  > func hello(_ id: Int) async { print(id) }
  > func launch() {
  >   Task { await hello(9) }
  > }
  > launch()
  > print(0)
  > SWIFT
  $ ./lab.exe --emit-sil infn.swift | grep -E -c '^sil @launch\$task0' || true
  1
  $ ./lab.exe build infn.swift -o infn && ./infn
  0
  9

Spawning survives `-O`: the optimizer must not merge, sink or delete a spawn (it is a call with
side effects), and the lifted task function must not be dropped as uncalled.

  $ ./lab.exe build conc.swift -O -o concO && ./concO
  0
  11
  21
  31
  12
  22
  32
  13
  23
  33
