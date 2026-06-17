# 35 · Machine code & the AAPCS64 / Apple ABI

**Objective:** make Backend B speak the platform **ABI** correctly. Concepts 33–34 handled the
common case (≤ 8 arguments, in registers); this concept fills the gap that makes the backend
*conformant*: **arguments beyond eight are passed on the stack**, and the **stack frame** is laid
out so it works on any frame size. Getting the ABI exactly right is what lets our code call (and be
called by) the platform — the same rules `swiftc` and `clang` follow.

**You edit:** `isel.ml` — `TODO(35a)`: place the 9th+ call argument in the outgoing stack area;
`TODO(35b)`: read the 9th+ parameter from the incoming stack area (via `x29`). The ≤ 8-argument
path, the frame layout (outgoing area sizing), and the large-frame-safe prologue/epilogue are given.

**Design oracle:** Apple's *Writing ARM64 Code for Apple Platforms* (the procedure call standard) —
specifically argument allocation (registers then stack), the frame record (`fp`/`lr`), and the
caller/callee split of the stack-argument area.

## What this concept adds
- **Stack-passed arguments (AAPCS64).** The first 8 integer arguments go in `x0`–`x7`; arguments
  9, 10, … go on the stack. The **caller** stores them into a reserved *outgoing* area at the bottom
  of its frame (`[sp, #0]`, `[sp, #8]`, …); the **callee** reads them via `x29` (the incoming `sp`),
  at `[x29, #16 + 8*j]` (the `+16` skips the saved `fp`/`lr`).
- **A large-frame-safe frame.** The prologue now pushes `fp`/`lr` first (a small, in-range
  adjustment) and *then* allocates the locals, so `stp`/`ldp` never blow their immediate range even
  when the frame is hundreds of bytes — a real bug concepts 33–34's single-`sub` frame hit on a
  12-argument function.

## Done when
`make lab C=phase8-arm64-backend/35-mc-abi` green: a 10- and a 12-argument function **run and match
`swiftc`** (across all three register-allocation rungs); the asm shows the outgoing stores and
`x29`-relative parameter loads and the offset-0 `stp` prologue; and ≤ 8-argument programs are
unchanged.

> **Scope (v0).** Integer arguments only (our corpus is `Int`/`Bool`, all 8-byte) — float-register
> (`d0`–`d7`) and aggregate-by-reference argument rules are documented but out of scope. "Machine
> code" in the literal sense — encoding instructions to 32-bit words and emitting a Mach-O object
> instead of assembly text — remains concept 33's exercise 5; here `clang` still assembles our `.s`.
