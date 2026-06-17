async / await + a cooperative executor: coroutines lowered to runtime calls, tasks round-robin.
RED until the TODO(38) hole (lowering `Task { … }` to a lifted coroutine + rt_async_spawn).

Sequential async matches swiftc exactly (it's deterministic — a chain of awaits):

  $ cat > seq.swift <<'SWIFT'
  > func compute(_ n: Int) async -> Int { return n * n }
  > func worker(_ id: Int) async {
  >   print(id * 10 + 1)
  >   await Task.yield()
  >   print(id * 10 + 2)
  > }
  > let a = await compute(6)
  > print(a)
  > let b = await compute(a)
  > print(b)
  > await worker(1)
  > await worker(2)
  > SWIFT
  $ ./lab.exe build seq.swift -o seq && ./seq
  36
  1296
  11
  12
  21
  22

Spawned tasks run on the cooperative executor — each yields, the scheduler round-robins them
(deterministic FIFO): main prints 0, then three tasks interleave round by round:

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

The lowering is runtime calls — no new SIL: `Task { }` -> a lifted coroutine + `rt_async_spawn`,
`Task.yield()` -> `rt_async_yield`, and main drains the executor with `rt_async_run`:

  $ ./lab.exe --emit-sil conc.swift | grep -c 'rt_async_spawn' || true
  3
  $ ./lab.exe --emit-sil conc.swift | grep -c 'rt_async_yield' || true
  2
  $ ./lab.exe --emit-sil conc.swift | grep -c 'rt_async_run' || true
  1
  $ ./lab.exe --emit-sil conc.swift | grep -c 'main$task' || true
  6
