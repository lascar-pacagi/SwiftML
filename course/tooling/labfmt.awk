# Reformat `dune build @<concept>/runtest` output into a progress report a learner can read:
#
#   PASS tests/lexer-strings.t (cram)
#     OK   a bad escape is reported at the character after the backslash
#   FAIL tests/lexer-operators.t (cram)
#     FAIL maximal munch: `==` is one token, not two `=`
#          the test wants:  ...
#          your code printed: ...
#     OK   the colon that introduces a type annotation
#
# Three things this must never do: hide a compile error (dune's `Error:` blocks pass through
# verbatim, first), call an unrun test PASS (a build failure makes everything after it SKIP), or
# reorder nondeterministically (dune emits in completion order, so sections are buffered).
#
# A cram case's sentence is the first sentence of the prose above it IN THE .t FILE — dune's diff
# only carries prose that lands in a context window, so the file itself is read. A case is FAIL if
# the diff mentions one of its commands; the rest ran and matched. Raw dune output: `make lab RAW=1`.

BEGIN {
  if (color) { B = "\033[1m"; R = "\033[31m"; G = "\033[32m"; C = "\033[36m"; D = "\033[2m"; Z = "\033[0m" }
}

function sec(kind, name,   key) {
  key = kind SUBSEP name
  if (!(key in idx)) { idx[key] = ++n; skind[n] = kind; sname[n] = name }
  cur = idx[key]
}
function put(line) { if (cur) body[cur] = body[cur] line "\n" }
function drop_pending() { pend = ""; pendfile = "" }

# ---- read a .t: the command roster, and one sentence per case ---------------
function first_sentence(p,   s) {
  gsub(/\n/, " ", p); gsub(/[[:space:]]+/, " ", p)
  s = p
  if (match(s, /\. /)) s = substr(s, 1, RSTART)          # first sentence
  sub(/[:.][[:space:]]*$/, "", s); sub(/^[[:space:]]+/, "", s)
  if (length(s) > 76) s = substr(s, 1, 75) "…"
  return s
}
function load_t(file,   line, blk, prose, started) {
  if (loaded[file]++) return
  blk = 0; prose = ""; started = 0
  while ((getline line < file) > 0) {
    if (line ~ /^  \$ /) {
      if (prose != "") { blk++; label[file, blk] = first_sentence(prose); prose = "" }
      if (blk > 0) cmdblk[file, substr(line, 3)] = blk   # keep "$ " so it matches the diff line
      nblk[file] = blk
    } else if (line !~ /^[[:space:]]/ && line != "") {
      if (started) prose = prose "\n" line; else { prose = line; started = 1 }
    } else if (line == "") started = 0
  }
  close(file)
}

# ---- section headers -------------------------------------------------------
/^File "/ {
  match($0, /"[^"]+"/); f = substr($0, RSTART + 1, RLENGTH - 2)
  flush(); drop_pending(); build = 0
  if (f ~ /\.t$/) { sub("^" prefix, "", f); sec("cram", f); tfile = prefix f; load_t(tfile); cram = 1 }
  else { cram = 0; pendfile = f; pend = $0 "\n" }        # maybe an error, maybe just dune noise
  next
}
/^Testing `/ {
  match($0, /`[^']+'/); sec("alcotest", substr($0, RSTART + 1, RLENGTH - 2))
  flush(); drop_pending(); cram = 0; build = 0; next
}

# ---- a dune / OCaml error: keep the whole block, verbatim ------------------
pendfile != "" && /^(Error|Warning)/ { sec("build", pendfile); put(pend $0); build = 1; pend = ""; next }
pendfile != "" { pend = pend $0 "\n"; next }
build { put($0); next }

# ---- cram: collect each command's wanted/produced output --------------------
function flush(   i, w, g, key) {
  if (nw || ng) {
    for (i = 1; i <= nw; i++) w = w "           " want[i] "\n"
    for (i = 1; i <= ng; i++) g = g "           " got[i] "\n"
    if (w != g) {
      key = cur SUBSEP pendblk; bad[key] = 1
      detail[key] = detail[key] "         " G "the test wants:" Z "\n" \
                    (w == "" ? "           (nothing)\n" : w) \
                    "         " R "your code printed:" Z "\n" \
                    (g == "" ? "           (nothing)\n" : g)
    }
  }
  nw = 0; ng = 0; split("", want); split("", got)
}

cram && /^(diff --git|index |--- |\+\+\+ |@@ )/ { next }
cram && /^[[:space:]]+\$ / { flush(); sub(/^[[:space:]]+/, ""); pendblk = cmdblk[tfile, $0]; next }
cram && /^-/  { sub(/^-[[:space:]]*/,  ""); want[++nw] = $0; next }
cram && /^\+/ { sub(/^\+[[:space:]]*/, ""); got[++ng] = $0; next }
cram && substr($0, 1, 3) == "   " { sub(/^[[:space:]]+/, ""); want[++nw] = $0; got[++ng] = $0; next }
cram { next }

# ---- alcotest: it lists every case in a failing suite, [FAIL] and [OK] alike -
/\[FAIL\]|\[OK\]/ {
  line = $0
  sub(/^> /, "", line); sub(/^[[:space:]]*/, "", line)
  sub(/^[|│][[:space:]]*/, "", line); sub(/[[:space:]]*[|│]$/, "", line); sub(/[[:space:]]+$/, "", line)
  ok = (line ~ /^\[OK\]/)
  sub(/^\[(FAIL|OK)\][[:space:]]*/, "", line)
  nf = split(line, a, /[[:space:]][[:space:]]+/)        # name, index, description
  if (nf >= 3) { desc = a[3]; for (k = 4; k <= nf; k++) desc = desc " " a[k]; line = a[1] " — " desc }
  sub(/\.$/, "", line)
  key = line; sub(/\.\.$/, "", key)                     # alcotest's box truncates 2 chars shorter
  if (!seen[cur SUBSEP substr(key, 1, 28)]++)
    put(ok ? "  " G "OK  " Z " " line : "  " R "FAIL" Z " " line)
  next
}
{ next }

END {
  flush()
  if (pendfile != "" && pend != "") { sec("build", pendfile); put(pend) }

  nr = split(cram_files, cf, " "); na = split(alcotest_suites, af, " ")
  for (k = 1; k <= nr; k++) if (cf[k] != "") roster[++nrost] = "cram" SUBSEP cf[k]
  for (k = 1; k <= na; k++) if (af[k] != "") roster[++nrost] = "alcotest" SUBSEP af[k]
  for (i = 1; i <= n; i++) {                            # failures not on the roster
    key = skind[i] SUBSEP sname[i]; if (body[i] == "" && !failedcram(i)) continue
    on = 0; for (k = 1; k <= nrost; k++) if (roster[k] == key) on = 1
    if (!on) roster[++nrost] = key
  }
  for (i = 1; i <= n; i++) if (skind[i] == "build" && body[i] != "") blocked = 1

  for (pass = 1; pass <= 3; pass++) {
    kind = (pass == 1) ? "build" : (pass == 2) ? "cram" : "alcotest"
    for (k = 1; k <= nrost; k++) {
      split(roster[k], part, SUBSEP); if (part[1] != kind) continue
      si = ((roster[k] in idx) ? idx[roster[k]] : 0)
      failing = (kind == "cram") ? (si && failedcram(si)) : (si && body[si] != "")
      if (failing) { printf "\n%s%sFAIL%s %s%s%s (%s)\n", B, R, Z, B, part[2], Z, kind; nfail++ }
      else if (blocked) { printf "%sSKIP%s %s (%s)\n", D, Z, part[2], kind; nskip++; continue }
      else { printf "%sPASS%s %s (%s)\n", G, Z, part[2], kind; npass++ }
      if (kind == "cram") show_cases(si, prefix part[2])
      else if (si) printf "%s", body[si]
    }
  }
  tail = nskip ? sprintf(", %d not run", nskip) : ""
  if (nfail) printf "\n%s%d passing, %d failing%s%s\n", B, npass, nfail, tail, Z
  else if (npass) printf "\n%s%d passing, 0 failing%s\n", G, npass, Z
  else printf "\n%sno tests ran%s\n", B, Z
}

function failedcram(si,   b, f) {                        # any case in this .t with a diff?
  for (b in bad) { split(b, p2, SUBSEP); if (p2[1] == si) return 1 }
  return 0
}
function show_cases(si, file,   b, key) {                # one OK/FAIL line per case, in file order
  load_t(file)
  for (b = 1; b <= nblk[file]; b++) {
    key = si SUBSEP b
    if (si && (key in bad)) { printf "  %sFAIL%s %s\n", R, Z, label[file, b]; printf "%s", detail[key] }
    else printf "  %sOK  %s %s\n", G, Z, label[file, b]
  }
}
