# 39 · Actors — serialized isolation

**Objective:** add Swift's `actor` — a reference type that **serializes access to its mutable
state**, so concurrent code can't race on it. The compiler enforces this: an actor's instance
methods can only be reached from outside with **`await`** (a *hop* onto the actor's executor); inside
the actor, access is synchronous. Actors are how Swift makes concurrency **data-race-free by
construction**, and the guarantee is a *compile-time* one.

**You edit:** `sema.ml` — `TODO(39)`: the **actor-isolation rule** — reject a synchronous,
non-awaited call to an actor's instance method from a nonisolated context. The actor declaration
(parsed and lowered as a reference type, reusing concept 25's class machinery) is given.

**Design oracle:** Swift's actor isolation (`swift/lib/Sema/TypeCheckConcurrency.cpp` — the
`ActorIsolation` checker), `SE-0306` (actors), and `SerialExecutor`.

## What this concept adds
- **`actor` declarations.** An actor is a **reference type** with isolated state — at runtime it
  reuses the whole class machinery (concept 25): a heap object, a vtable, `init`, methods. The new
  thing is entirely in the type checker.
- **The isolation rule.** Calling `a.method()` on an actor `a` from a nonisolated context (outside
  the actor, not under `await`) is a compile error: *"call to actor-isolated instance method '…' in
  a synchronous nonisolated context."* Wrapping it in `await a.method()` is the hop that's allowed.
  Inside the actor's own methods, `self`-access (and calls to its own methods) are synchronous.

## Done when
`make lab C=phase8-arm64-backend/39-actors` green: an actor runs and matches `swiftc` (state mutated
through awaited calls); a synchronous non-awaited actor call is rejected with `swiftc`'s wording;
inside-actor access is synchronous; a regular `class` is unaffected.

> **Scope & honesty (v0).** Actors **reuse the class runtime** — and because our executor (concept
> 38) is single-threaded and cooperative, the *runtime* serialization is automatic (there's no true
> parallelism to race). So the lesson here is the **compile-time isolation rule**, which is the part
> that makes actors valuable; the runtime queue-hop that a multi-threaded executor needs is
> documented but degenerate in our serial model. The rule covers instance-method calls; property
> isolation, `nonisolated`, global actors (`@MainActor`), and `Sendable` checking are the next
> layers (exercises).
