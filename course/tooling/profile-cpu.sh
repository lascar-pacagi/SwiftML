#!/usr/bin/env bash
# Sampled CPU profile of a concept's benchmark, using the macOS `sample` tool.
#
#   ./tooling/profile-cpu.sh phase1-minimal/01-lexer      (or: make profile-cpu C=...)
#
# `make profile` measures what the program allocates; this measures where the CPU
# actually sits, including time inside the OCaml runtime (minor collections, marking,
# sweeping) that no in-process counter can attribute to a source line.
set -uo pipefail

C="${1:?usage: profile-cpu.sh <concept-dir> [v0|v1], e.g. phase1-minimal/01-lexer v1}"
# profile.exe --spin RUNG is a steady single-rung workload: no Memprof, no equivalence
# check, and one rung at a time so the samples are not split between them.
RUNG="${2:-${RUNG:-v0}}"
case "$RUNG" in
  v0 | v1) ;;
  *)
    echo "unknown rung '$RUNG' (expected v0 or v1)"
    exit 1
    ;;
esac
exe="_build/default/${C}/bench/profile.exe"
args="--spin"
secs="${SAMPLE_SECONDS:-5}"

command -v sample >/dev/null 2>&1 || { echo "\`sample\` not found (macOS only)."; exit 1; }
[ -x "$exe" ] || { echo "no profile binary at $exe — run: make build"; exit 1; }

out="${TMPDIR:-/tmp}/swiftml-profile-cpu-${RUNG}.txt"
rm -f "$out"     # never report a stale profile from an earlier run
"$exe" $args $((secs + 3)) "$RUNG" >/dev/null 2>&1 &
pid=$!
sleep 0.4
kill -0 "$pid" 2>/dev/null || { echo "the $RUNG workload exited immediately — is it implemented?"; exit 1; }
sample "$pid" "$secs" -file "$out" >/dev/null 2>&1
wait "$pid" 2>/dev/null

[ -s "$out" ] || { echo "sample produced no output for $RUNG"; exit 1; }
echo "workload: $RUNG"


python3 - "$out" <<'PY'
import re, sys

text = open(sys.argv[1], errors="replace").read()
m = re.search(r"Sort by top of stack.*?\n(.*?)(\n\n|\Z)", text, re.S)
if not m:
    print("could not find the flat profile in sample's output"); sys.exit(1)

rows = []
for line in m.group(1).splitlines():
    mm = re.match(r"\s*(.+?)\s+\(in .*?\)\s+(\d+)\s*$", line)
    if mm:
        rows.append((mm.group(1), int(mm.group(2))))

GC = re.compile(r"(do_some_marking|oldify|pool_sweep|sweep|mark_|caml_call_gc|caml_alloc|"
                r"caml_shared_try_alloc|minor_heap|major_slice|try_update_object_header|"
                r"caml_do_pending_actions|caml_poll_gc_work|caml_empty_minor|caml_garbage)")

def demangle(f):
    # camlDune__exe__Lexer_v1_fast$skip_450 -> Lexer_v1_fast.skip ; camlLexer$next_389 -> Lexer.next
    mm = re.match(r"caml(?:Dune__exe__)?([A-Za-z0-9_]+)\$([a-zA-Z0-9_']+?)(?:_\d+)?$", f)
    if mm:
        return "%s.%s" % (mm.group(1).replace("Stdlib__", ""), mm.group(2))
    return f

def bucket(f):
    if GC.search(f): return "gc"
    if re.match(r"caml[A-Z]", f) or f.startswith("camlDune"): return "ocaml"
    return "runtime"

total = sum(n for _, n in rows) or 1
gc  = sum(n for f, n in rows if bucket(f) == "gc")
ml  = sum(n for f, n in rows if bucket(f) == "ocaml")
oth = total - gc - ml
ngc = len([1 for f, _ in rows if bucket(f) == "gc"])
nml = len([1 for f, _ in rows if bucket(f) == "ocaml"])
noth = len(rows) - ngc - nml

print("CPU profile — %d samples at the top of the stack\n" % total)
print("   %-42s %8s  %s" % ("frame", "samples", "share"))
print("   " + "-" * 66)
for f, n in rows[:15]:
    tag = {"gc": "[GC]", "ocaml": "", "runtime": "[rt]"}[bucket(f)]
    print("   %-42s %8d  %5.1f%% %s" % (demangle(f)[:42], n, 100.0 * n / total, tag))
print()
shown = sum(n for _, n in rows[:15])
print("   (the table lists the top 15 of %d frames = %.1f%% of samples; the shares below" %
      (len(rows), 100.0 * shown / total))
print("    are over ALL frames, so they do not add up from the rows above)\n")
print("   OCaml code (yours + stdlib)  %5.1f%%   %d frames" % (100.0 * ml / total, nml))
print("   GC / allocator               %5.1f%%   %d frames" % (100.0 * gc / total, ngc))
print("   other runtime                %5.1f%%   %d frames" % (100.0 * oth / total, noth))
print()
if gc > ml:
    print("   => More CPU goes into collecting garbage than into lexing. That is an")
    print("      ALLOCATION problem, not a scanning one — `make profile` section 4 names")
    print("      the lines that allocate; stop allocating there and this whole column shrinks.")
else:
    print("   => Most CPU is in your own code; look at the hottest frames above and at")
    print("      `make profile` section 1 to see which construct they serve.")
PY
