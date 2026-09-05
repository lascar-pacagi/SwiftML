GREEN before you start: `async`, `await` and `Task.yield()` are given, and this file fixes what
they mean before you lower a single task. Read it first.

`await` is TRANSPARENT. On a serial executor an `await` of an async function is an ordinary
call — the lowering adds no instruction at all, and the SIL of an awaiting program contains no
runtime call beyond what the body itself asks for.

  $ printf 'func f() async -> Int { return 5 }\nlet x = await f()\nprint(x)\n' > t.swift
  $ ./lab.exe --emit-sil t.swift | grep -c 'rt_async_spawn' || true
  0
  $ ./lab.exe --emit-sil t.swift | grep -c 'rt_async_yield' || true
  0
  $ ./lab.exe --emit-sil t.swift | grep -c 'apply @f' || true
  0

`Task.yield()` is the one suspension point, and it is a plain runtime call — no new SIL
instruction, the same trick concepts 30 and 31 used for errors and arrays.

  $ printf 'func w() async {\n  print(1)\n  await Task.yield()\n  print(2)\n}\nawait w()\n' > y.swift
  $ ./lab.exe --emit-sil y.swift | grep -c 'rt_async_yield' || true
  1
  $ ./lab.exe build y.swift -o y && ./y
  1
  2
  $ swiftc -Onone y.swift -o y_sw && ./y_sw
  1
  2

`main` ends by draining the executor, exactly once, so anything spawned during the program gets
to run before the process exits.

  $ ./lab.exe --emit-sil y.swift | grep -c 'rt_async_run' || true
  1

v0 TASK BODIES CAPTURE NOTHING, and that is enforced rather than assumed. A task is enqueued and
runs after the statement that spawned it, so its context would have to outlive the scope — and a
v0 context is empty. Reading an enclosing binding is a diagnostic. NOTE this is OUR restriction:
swiftc accepts the same program, because its task contexts are real.

  $ printf 'func w(_ n: Int) async { print(n) }\nlet k = 7\nTask { await w(k) }\nprint(0)\n' > cap.swift
  $ ./lab.exe --typecheck cap.swift
  3:16: error: cannot capture 'k' in a task body in this subset (a task runs after the scope that spawned it; pass it to the function the task calls instead)
  [1]
  $ swiftc -typecheck cap.swift && echo "swiftc accepts it"
  swiftc accepts it
