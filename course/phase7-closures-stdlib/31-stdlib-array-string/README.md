# 31 · Array & String (the stdlib begins)

**Objective:** build `Array<Int>` and `String` in our own subset, on the **heap**, with
**value semantics via copy-on-write**. An array is a pointer to a refcounted buffer
`{ refcount, count, capacity, data }`; a binding *shares* the buffer (retain), and a mutation
*copies it iff it is shared* (the CoW check). String is a libc C-string with concat + length.
These are the first types whose runtime lives in **intrinsics** (`rt.array_*` / `rt.str_*`),
not in new SIL — the same trick as concept 30.

**You edit:** `silgen.ml` — `TODO(31a)`: the **`append` copy-on-write dance** (load the buffer
pointer, `make_unique` it, store the unique pointer back, then push); `TODO(31b)`: the **same
dance for `a[i] = e`** (ending in `array_set`). The literal/subscript-read/`count`/`for-in`/
String lowering and the whole `rt.*` runtime are given.

**Design oracle:** `../../../swift/stdlib/public/core/Array.swift` &
`ContiguousArrayBuffer.swift` (the real CoW buffer + `isKnownUniquelyReferenced`),
`String.swift` (the small-string/bridged representation we simplify to a C-string).

## What this concept adds
- **`[T]` types**, **array literals** `[a, b, c]`, **subscript** `a[i]` (read + write),
  **`a.append(x)`**, **`a.count`** / **`a.isEmpty`**, and **`for x in a`** iteration.
- a **refcounted heap buffer** with a growable (`double, min 4`) backing store, and
  **bounds-checked** access that **traps** (exit 133, "Index out of range") like swiftc.
- **copy-on-write value semantics**: `var b = a` retains the shared buffer; the first mutation of
  either binding calls `rt.array_make_unique` (copies only when `refcount > 1`).
- **`String`**: literals, `+` concatenation (`rt.str_concat`), `.count` (byte length), `print`.

> **Scope (v0).** Element type is **`Int`** only — the buffer is a homogeneous `i64` store, so
> `[String]`/`[Bool]` are rejected up front (a clean diagnostic, not a miscompile). An
> element-generic buffer (zext/ptr-cast at the boundary), `remove`/`insert`/`+` on arrays,
> `[T](repeating:count:)`, and full ARC release on scope exit are the exercises. String is
> byte-indexed ASCII; Unicode grapheme semantics are the documented divergence.

## Done when
`make lab C=phase7-closures-stdlib/31-stdlib-array-string` green: an array program (literal,
count, subscript r/w, append, for-in) and a String program match `swiftc` byte-for-byte at
`-Onone` and `-O`; `var b = a` then mutating `b` leaves `a` unchanged (CoW); out-of-bounds
exits 133.
