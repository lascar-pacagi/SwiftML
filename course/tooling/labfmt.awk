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
  if (color) { B = "\033[1m"; R = "\033[31m"; G = "\033[32m"; C = "\033[36m"; D = "\033[2m"; Y = "\033[33m"; Z = "\033[0m" }
}

{ clean = $0; gsub(/\033\[[0-9;]*m/, "", clean) }   # ANSI-free copy, for the matchers below

function sec(kind, name,   key) {
  key = kind SUBSEP name
  if (!(key in idx)) { idx[key] = ++n; skind[n] = kind; sname[n] = name }
  cur = idx[key]
}
function put(line) { if (cur) body[cur] = body[cur] line "\n" }
function drop_pending() { pend = ""; pendfile = "" }

# Which stage of the pipeline a test belongs to: tests/lexer-strings.t -> lexer, and the
# alcotest suite parser-types -> parser. Grouping by it is what lets the report say a whole
# stage is finished, which a per-file list never quite does.
function stage(kind, name,   b) {
  b = name; sub(/^.*\//, "", b); sub(/\.t$/, "", b)
  if (match(b, /-/)) b = substr(b, 1, RSTART - 1)
  return b
}

# ---- read a .t: the command roster, and one sentence per case ---------------
function first_sentence(p,   s) {
  gsub(/\n/, " ", p); gsub(/[[:space:]]+/, " ", p)
  s = p
  if (match(s, /\. /)) s = substr(s, 1, RSTART)          # first sentence
  sub(/[:.][[:space:]]*$/, "", s); sub(/^[[:space:]]+/, "", s)
  if (length(s) > 76) s = trunc_utf8(s, 75) "…"
  return s
}
# awk here is byte-oriented: a cut inside a multibyte character (an em dash, a `…`) leaves a
# partial sequence that later aborts the run ("towc: multibyte conversion failure").
function trunc_utf8(s, n,   b) {
  if (!("\200" in ord)) for (b = 0; b < 256; b++) ord[sprintf("%c", b)] = b
  s = substr(s, 1, n)
  while (length(s) && ord[substr(s, length(s), 1)] >= 128 && ord[substr(s, length(s), 1)] < 192)
    s = substr(s, 1, length(s) - 1)                         # continuation bytes
  if (length(s) && ord[substr(s, length(s), 1)] >= 192) s = substr(s, 1, length(s) - 1)  # lone lead
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
    } else if (line ~ /^  > / && blk > 0) {
      cmdblk[file, substr(line, 3)] = blk                # a continuation line of that command
    } else if (line !~ /^[[:space:]]/ && line != "") {
      if (started) prose = prose "\n" line; else { prose = line; started = 1 }
    } else if (line == "") started = 0
  }
  close(file)
}

# ---- section headers -------------------------------------------------------
/^File "/ {
  match($0, /"[^"]+"/); f = substr($0, RSTART + 1, RLENGTH - 2)
  flush(); drop_pending(); build = 0; pendblk = ""
  if (f ~ /\.t$/) { sub("^" prefix, "", f); sec("cram", f); tfile = prefix f; load_t(tfile); cram = 1 }
  else { cram = 0; pendfile = f; pend = $0 "\n" }        # maybe an error, maybe just dune noise
  next
}
/^Testing `/ {
  match($0, /`[^']+'/); sec("alcotest", substr($0, RSTART + 1, RLENGTH - 2))
  flush(); drop_pending(); cram = 0; build = 0; next
}

# ---- a dune / OCaml error: keep the whole block, verbatim ------------------
# Alcotest prints the useful part of a failure between the box and the stack trace: the ASSERT
# label (which case), then either an [exception]/[failure] line or Expected/Received. Keep those,
# drop the trace — a bare case name does not tell you what went wrong.
!cram && clean ~ /^ *ASSERT / {
  line = clean; sub(/^ *ASSERT */, "", line)
  if (line ~ /expected exactly|got [0-9]+$/) {            # an Alcotest.failf message, not a label
    if (curcase != shown_case) { put("       " D "└ " curcase Z); shown_case = curcase }
    put("         " R "failed:" Z " " line); next
  }
  if (curcase != shown_case) { put("       " D "└ " curcase Z); shown_case = curcase }
  put("         " D "ran:  " Z " " line); next
}
# alcotest prints a BARE `FAIL "<label>"` for the check that actually failed, after the ASSERT
# lines for the checks that merely ran. That line is the answer to "what is wrong", so keep it.
!cram && clean ~ /^FAIL "/ {
  line = clean; sub(/^FAIL */, "", line)
  if (curcase != shown_case) { put("       " D "└ " curcase Z); shown_case = curcase }
  put("         " R "failed:" Z " " line); next
}
!cram && clean ~ /^\[(exception|failure)\]/ {
  line = clean; sub(/^\[[a-z]*\] */, "", line)
  put("         " R "error:" Z " " line); next
}
!cram && clean ~ /^ *(Expected|Received):/ {
  line = clean; sub(/^ */, "", line)
  put("         " line); next
}
pendfile != "" && /^Error/ { sec("build", pendfile); put(pend $0); build = 1; pend = ""; next }
pendfile != "" && /^Warning/ { drop_pending(); next }   # a warning is not a failure
pendfile != "" { pend = pend $0 "\n"; next }
build { put($0); next }

# ---- cram: collect each command's wanted/produced output --------------------
function flush(   i, w, g, key) {
  if (nw || ng) {
    for (i = 1; i <= nw; i++) w = w "           " want[i] "\n"
    for (i = 1; i <= ng; i++) g = g "           " got[i] "\n"
    if (w != g) {
      key = cur SUBSEP pendblk; bad[key] = 1
      if (g ~ /Failure\("TODO/) todo[key] = 1        # the skeleton's own failwith, not a wrong answer
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
# a hunk may open in the middle of a multi-line command (`  > …`): those lines name it too
cram && /^[[:space:]]+> / && pendblk == "" { sub(/^[[:space:]]+/, ""); pendblk = cmdblk[tfile, $0]; next }
cram && /^-/  { sub(/^-[[:space:]]*/,  ""); want[++nw] = $0; next }
cram && /^\+/ { sub(/^\+[[:space:]]*/, ""); got[++ng] = $0; next }
cram && substr($0, 1, 3) == "   " { sub(/^[[:space:]]+/, ""); want[++nw] = $0; got[++ng] = $0; next }
cram { next }

# ---- alcotest: it lists every case in a failing suite, [FAIL] and [OK] alike -
/\[SKIP\]/ {                                            # a case that chose not to run (see the suite's note)
  line = clean; sub(/^[^[]*\[SKIP\][[:space:]]*/, "", line); sub(/[[:space:]]+$/, "", line)
  nf = split(line, a, /[[:space:]][[:space:]]+/)
  if (nf >= 3) { desc = a[3]; for (k = 4; k <= nf; k++) desc = desc " " a[k]; line = a[1] " — " desc }
  sub(/\.$/, "", line)
  if (!seen[cur SUBSEP "skip" SUBSEP line]++) {
    if (!skipnote[cur]++) put("  " D "(skip: the suite chose not to run it — the reason sits next to `Alcotest.skip` in its .ml)" Z)
    put("  " D "skip " line Z)
  }
  next
}
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
  # A group reporting itself "skipped — … not started" is OPTIONAL work (a §6 exercise), not a
  # pass: show it as TODO so it stays visible, and keep it out of both counts.
  if (line ~ / — skipped/) {
    sub(/ — skipped.*$/, "", line)
    if (!seen[cur SUBSEP line]++) { put("  " Y "TODO" Z " " line D " (optional)" Z); nopt[cur]++ }
    next
  }
  if (!ok) curcase = a[1]        # the box repeats this line just before the failure detail
  if (!seen[cur SUBSEP substr(key, 1, 28)]++) {
    if (ok) nok[cur]++; else nbad[cur]++
    put(ok ? "  " G "OK  " Z " " line : "  " R "FAIL" Z " " line)
  }
  next
}
{ next }

END {
  flush()
  # A pending File block that never produced an `Error:` line is dune noise (it heads a test
  # action's output), not a build failure — turning it into one used to mark everything after
  # it SKIP, i.e. claim tests hadn't run when they had.

  nr = split(cram_files, cf, " "); na = split(alcotest_suites, af, "|")   # suite names may contain spaces
  for (k = 1; k <= nr; k++) if (cf[k] != "") roster[++nrost] = "cram" SUBSEP cf[k]
  for (k = 1; k <= na; k++) if (af[k] != "") roster[++nrost] = "alcotest" SUBSEP af[k]
  for (i = 1; i <= n; i++) {                            # failures not on the roster
    key = skind[i] SUBSEP sname[i]; if (body[i] == "" && !failedcram(i)) continue
    on = 0; for (k = 1; k <= nrost; k++) if (roster[k] == key) on = 1
    if (!on) roster[++nrost] = key
  }
  for (i = 1; i <= n; i++) if (skind[i] == "build" && body[i] != "") blocked = 1

  # build errors first: they block everything, and nothing after them ran
  for (k = 1; k <= nrost; k++) {
    split(roster[k], part, SUBSEP); if (part[1] != "build") continue
    si = idx[roster[k]]
    printf "\n%s%sFAIL%s %s%s%s (build)\n", B, R, Z, B, part[2], Z; nfail++
    printf "%s", body[si]
  }

  # then one group per stage, in name order, cram files before alcotest suites
  for (k = 1; k <= nrost; k++) {
    split(roster[k], part, SUBSEP); if (part[1] == "build") continue
    st = stage(part[1], part[2])
    if (!(st in seenstage)) { seenstage[st] = ++nstage; stname[nstage] = st }
    stof[k] = st
  }
  for (gi = 1; gi <= nstage; gi++)
    for (gj = gi + 1; gj <= nstage; gj++)
      if (stname[gj] < stname[gi]) { t = stname[gi]; stname[gi] = stname[gj]; stname[gj] = t }

  for (gi = 1; gi <= nstage; gi++) {
    st = stname[gi]; total = 0; good = 0; out = ""
    for (pass = 1; pass <= 2; pass++) {
      kind = (pass == 1) ? "cram" : "alcotest"
      for (k = 1; k <= nrost; k++) {
        split(roster[k], part, SUBSEP)
        if (part[1] != kind || stof[k] != st) continue
        si = ((roster[k] in idx) ? idx[roster[k]] : 0)
        # An alcotest suite fails only if it printed a [FAIL] line: dune shows a SUCCESSFUL
        # suite's output too when a sibling in the same stanza fails, so "has output" is not
        # "has failed" — believing that reported a green suite as red.
        failing = (kind == "cram") ? (si && failedcram(si)) : (si && nbad[si] > 0)
        optional = (kind == "alcotest" && si && nopt[si] > 0 && nbad[si] == 0)
        tf = prefix part[2]; unstarted = 0
        if (failing && kind == "cram") unstarted = (nblk[tf] > 0 && nfailing(si, tf) == nblk[tf])
        else if (failing) unstarted = (nbad[si] > 0 && nok[si] == 0)
        total++
        if (optional) {
          out = out sprintf("%s%sTODO%s %s%s%s (%s) — optional\n", B, Y, Z, B, part[2], Z, kind)
          nopts++
        } else if (unstarted && !detail_all) {
          out = out sprintf("%s%sTODO%s %s%s%s (%s) — not started\n", B, Y, Z, B, part[2], Z, kind)
          ntodo++
        } else if (failing) {
          out = out sprintf("%s%sFAIL%s %s%s%s (%s)\n", B, R, Z, B, part[2], Z, kind); nfail++
        } else if (blocked) {
          out = out sprintf("%sSKIP%s %s (%s)\n", D, Z, part[2], kind); nskip++; continue
        } else {
          out = out sprintf("%sPASS%s %s (%s)\n", G, Z, part[2], kind); npass++; good++
        }
        if (kind == "cram") out = out cases_str(si, tf, unstarted)
        else if (si) {
          b2 = body[si]
          if (unstarted && !detail_all) gsub(/  \033\[31mFAIL\033\[0m |  FAIL /, "  " D "·" Z "    ", b2)
          out = out b2
        }
      }
    }
    if (total == 0) continue
    if (good == total) printf "\n%s%s── %s: COMPLETE (%d/%d) ✔%s\n", B, G, st, good, total, Z
    else if (out ~ /— optional/ && out !~ /FAIL|not started/)
      printf "\n%s── %s: optional%s\n", B, st, Z
    else printf "\n%s── %s: %d of %d passing%s\n", B, st, good, total, Z
    printf "%s", out
  }

  tail = (ntodo ? sprintf(", %d not started", ntodo) : "") (nopts ? sprintf(", %d optional", nopts) : "") (nskip ? sprintf(", %d not run", nskip) : "")
  if (nfail || ntodo) printf "\n%s%d passing, %d failing%s%s\n", B, npass, nfail, tail, Z
  else if (npass) printf "\n%s%d passing, 0 failing%s\n", G, npass, Z
  else printf "\n%sno tests ran%s\n", B, Z
}

function failedcram(si,   b, f) {                        # any case in this .t with a diff?
  for (b in bad) { split(b, p2, SUBSEP); if (p2[1] == si) return 1 }
  return 0
}
function nfailing(si, file,   b, c) {
  for (b = 1; b <= nblk[file]; b++) if (si SUBSEP b in bad) c++
  return c
}
# One OK/FAIL line per case, in file order. When EVERY case fails the hole hasn't been started,
# so the diffs are noise — list what the file will check and leave it at that (DETAIL=1 expands).
function cases_str(si, file, unstarted,   b, key, out) {
  load_t(file)
  unstarted = unstarted && !detail_all
  for (b = 1; b <= nblk[file]; b++) {
    key = si SUBSEP b
    if (si && (key in bad)) {
      if (unstarted) { out = out sprintf("  %s·%s   %s\n", D, Z, label[file, b]); continue }
      out = out sprintf("  %sFAIL%s %s\n", R, Z, label[file, b])
      if (key in todo) out = out sprintf("         %snot implemented yet (the skeleton's failwith)%s\n", D, Z)
      else out = out detail[key]
    } else out = out sprintf("  %sOK  %s %s\n", G, Z, label[file, b])
  }
  if (unstarted) out = out sprintf("       %snothing here passes yet — DETAIL=1 to see the diffs%s\n", D, Z)
  return out
}
