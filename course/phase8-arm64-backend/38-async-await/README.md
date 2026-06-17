# 38 · async / await — coroutines & a cooperative executor

**Objective:** add Swift's concurrency surface — `async` functions, `await`, `Task { … }`, and
`Task.yield()` — to the language, lowered onto a **cooperative executor** with real **coroutines**.
A task can *suspend* at a yield point and *resume* later; the executor round-robins ready tasks.
This is the concurrency model that makes `async`/`await` work, built from scratch.

**You edit:** `silgen.ml` — `TODO(38)`: lower `Task { … }` to a **lifted coroutine** (a function the
executor runs) + an `rt_async_spawn` call. The `await`/`Task.yield()` lowering, the main-drains-the-
executor epilogue, and the C coroutine runtime are given.

**Design oracle:** Swift's `_Concurrency` runtime (`Task`, executors, `withTaskGroup`), and the
`AsyncFunction` SIL lowering. The classic split: swiftc uses **stackless** coroutines (CPS state
machines); we use **stackful** coroutines (a stack per task) for simplicity — same semantics.

## What this concept adds
- **`async` / `await`.** `func f() async -> T` and `await e`. Sequential async is **deterministic
  and matches `swiftc` exactly** (a chain of awaits). `await` is a suspension *marker*; the actual
  suspension happens at yield points.
- **`Task { … }` + `Task.yield()`.** Spawn a concurrent task (a coroutine); yield cooperatively to
  the executor. Our executor is a **serial, deterministic, FIFO round-robin** scheduler.
- **The runtime, in C** (given, linked): each task is a **stackful coroutine** (`ucontext` — its own
  stack); `rt_async_spawn` enqueues, `rt_async_yield` suspends, `rt_async_run` drains the queue. The
  whole feature is **runtime calls — zero new SIL** (the same trick as errors and arrays).

## Done when
`make lab C=phase8-arm64-backend/38-async-await` green: sequential async matches `swiftc`
(`36 1296`, `11 12 21 22`); spawned tasks interleave round-robin on our executor
(`0 11 21 31 12 22 32 …`); the SIL shows the `rt_async_*` calls and the lifted task coroutines.

> **Scope & honesty (v0).** We model a **serial cooperative executor** (deterministic); Swift's
> default global executor is **concurrent / multi-threaded** (so its `Task {}` interleaving is
> nondeterministic — which is why we match `swiftc` only on the *deterministic* sequential-async
> programs, and verify interleaving against our own documented FIFO semantics). Task bodies are
> **capture-free** in v0 (they call top-level functions); managed captures would need the runtime to
> own the context (an exercise). `withTaskGroup`, `async let`, cancellation, and actor hops (concept
> 39) are the next layers.
