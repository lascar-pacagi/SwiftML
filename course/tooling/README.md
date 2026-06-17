# tooling/ — the harnesses

Shared test/measurement harnesses used across every concept.

| Tool | What it does |
|---|---|
| `oracle.sh <file.swift>` | **The headline check.** Compiles a program with both `swiftml` and the real `swiftc`, runs both, and diffs stdout + exit code. Exit 0 = behavior matches. `make oracle F=…`. |
| `filecheck.sh <checkfile>` | A tiny `FileCheck`: assert the *shape* of `--emit-tokens/-ast/-sil/-llvm` and diagnostics with `// CHECK:` / `CHECK-NEXT:` / `CHECK-NOT:` lines. Defers to LLVM's real `FileCheck` if it's on PATH. |
| `bench/` (per concept) | Compile-throughput + generated-code-runtime measurement, reported relative to `swiftc -Onone`/`-O`. |

Most integration tests are **dune cram tests** (`tests/*.t`) — they run a command and diff against
golden output, which covers exact-match assertions. Use `filecheck.sh` when you want *partial /
ordered* matching instead of an exact golden file.

The behavioral oracle needs `swiftc` (`/usr/bin/swiftc`, already installed). The design oracle is
the read-only `../../swift/` source tree — read it, never edit it.
