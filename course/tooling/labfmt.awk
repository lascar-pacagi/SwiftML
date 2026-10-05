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
  ns = split(skipped_cram, sf, " ")
  for (i = 1; i <= ns; i++) if (sf[i] != "") explicitly_skipped[sf[i]] = 1
  ns = split(skipped_alcotest, sf, " ")
  for (i = 1; i <= ns; i++) if (sf[i] != "") explicitly_skipped_alcotest[sf[i]] = 1
  # A staged run filters the unit suite to the groups belonging to this stage, and alcotest
  # prints every case it did NOT select as [SKIP]. Those are not the suite declining to run a
  # case — they are a later stage's work, so drop them. A group's cases are named after the cram
  # file beside them, which is what makes this stage's own file list the filter.
  ns = split(stage_groups, sf, " ")
  for (i = 1; i <= ns; i++)
    if (sf[i] != "") { g = sf[i]; sub(/^tests\//, "", g); sub(/\.t$/, "", g); this_stage[g] = 1; have_stage_groups = 1 }
}

{ clean = $0; gsub(/\033\[[0-9;]*m/, "", clean) }   # ANSI-free copy, for the matchers below

# Alcotest keeps every case's full log in this directory, one file per case: the console shows
# the details of the FIRST failure only, so a case's own log is the only place that says whether
# it stopped at an unwritten TODO(NN).
/Full test results in `/ {
  p = clean; sub(/.*Full test results in `/, "", p); sub(/'.*$/, "", p)
  sub(/^~/, ENVIRON["HOME"], p)
  if (cur) resdir[cur] = p
  # alcotest's failure box names the test file (`File "…test_x.ml", line N`), which the build-
  # error rule below takes for the start of an error block and then swallows every line to the
  # next `Error`: this line must be read before that, so it sits up here
}

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
  if (kind == "alcotest" && stage_name != "") return stage_name   # the stage that ran it
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
  return s
}
# Wrap a case label instead of cutting it: a truncated sentence loses exactly the half that says
# what the case expects. Breaks on spaces, continues under the label's first column.
function wrap_label(s, width,   out, line, n, i, a, w) {
  if (!("\200" in ord)) for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
  n = split(s, a, " ")
  line = ""; out = ""
  for (i = 1; i <= n; i++) {
    w = a[i]
    if (line == "") line = w
    else if (vislen(line " " w) <= width) line = line " " w
    else { out = out line "\n       "; line = w }
  }
  return out line
}
# length in characters, not bytes — a UTF-8 lead byte counts once, continuations not at all
function vislen(s,   i, c, n) {
  for (i = 1; i <= length(s); i++) {
    c = ord[substr(s, i, 1)]
    if (c < 128 || c >= 192) n++
  }
  return n
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
# The Swift program a case runs on lives in its own setup command — a `printf '…' > x.swift`
# or a `cat > x.swift <<'EOF'` heredoc. Keeping it is what lets a failure show the INPUT: two
# AST dumps that differ tell you nothing until you can see the line of Swift that produced them.
function printf_body(cmd,   s, q) {
  if (cmd !~ /^printf (-- )?'/) return ""
  s = substr(cmd, index(cmd, "'") + 1)
  q = index(s, "'")
  if (q > 0) s = substr(s, 1, q - 1)
  gsub(/\\n/, "\n", s); gsub(/\\t/, "\t", s)
  sub(/\n$/, "", s)
  return s
}
# the file a setup command writes to: `… > prog.swift`, never the `2>&1` of a run command
function redirect_target(cmd,   t) {
  if (!match(cmd, />[[:space:]]*[A-Za-z0-9_.\/-]+\.(swift|txt)/)) return ""
  t = substr(cmd, RSTART, RLENGTH); sub(/^>[[:space:]]*/, "", t)
  return t
}
function load_t(file,   line, blk, prose, started, ln, here, hereblk, cmd, cont, body, b, words, nw2, wa, i2) {
  if (loaded[file]++) return
  blk = 0; prose = ""; started = 0; ln = 0; here = 0
  while ((getline line < file) > 0) {
    lineblk[file, ++ln] = blk                          # which command's block owns this line
    if (line ~ /^  \$ /) {
      if (prose != "") { blk++; label[file, blk] = first_sentence(prose); prose = "" }
      if (blk > 0) cmdblk[file, substr(line, 3)] = blk   # keep "$ " so it matches the diff line
      nblk[file] = blk
      here = 0
      if (blk > 0) {
        cmd = substr(line, 5)
        blkcmd[file, blk] = blkcmd[file, blk] " " cmd
        body = printf_body(cmd)
        if (body != "") {
          srcblk[file, blk] = body; srcname[file, blk] = redirect_target(cmd)
          if (srcname[file, blk] != "") srcfile[file, srcname[file, blk]] = body
        } else if (match(cmd, /<<[[:space:]]*'?[A-Za-z_]+'?/)) {  # a heredoc opens; its body follows
          here = substr(cmd, RSTART, RLENGTH); gsub(/[<[:space:]']/, "", here)
          srcblk[file, blk] = ""; hereblk = blk; srcname[file, blk] = redirect_target(cmd)
        }
      }
    } else if (line ~ /^  > / && blk > 0) {
      cmdblk[file, substr(line, 3)] = blk                # a continuation line of that command
      if (here != 0) {
        cont = substr(line, 5)
        if (cont == here) {
          here = 0
          if (srcname[file, hereblk] != "") srcfile[file, srcname[file, hereblk]] = srcblk[file, hereblk]
        } else srcblk[file, blk] = srcblk[file, blk] (srcblk[file, blk] == "" ? "" : "\n") cont
      }
    } else if (line !~ /^[[:space:]]/ && line != "") {
      if (started) prose = prose "\n" line; else { prose = line; started = 1 }
    } else if (line == "") started = 0
  }
  close(file)
  # A case often runs against a file an earlier case created. Resolve those by name, so the
  # report shows the program for every case, not only the one that happened to write it.
  for (b = 1; b <= nblk[file]; b++) {
    if ((file SUBSEP b) in srcblk && srcblk[file, b] != "") continue
    words = blkcmd[file, b]; gsub(/[^A-Za-z0-9_.\/-]/, " ", words)
    nw2 = split(words, wa, " ")
    for (i2 = 1; i2 <= nw2; i2++)
      if ((file SUBSEP wa[i2]) in srcfile) {
        srcblk[file, b] = srcfile[file, wa[i2]]; srcname[file, b] = wa[i2]; break
      }
  }
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
  # flush FIRST: a cram diff that ends where an alcotest suite begins is still the CRAM file's
  # failure, and `sec` moves `cur`. Filing it under the suite that happens to follow made dune's
  # own red report as PASS — `/^File "/` above has always had this order.
  flush(); drop_pending()
  match($0, /`[^']+'/); sec("alcotest", substr($0, RSTART + 1, RLENGTH - 2))
  cram = 0; build = 0; next
}

# ---- a dune / OCaml error: keep the whole block, verbatim ------------------
# Alcotest prints the useful part of a failure between the box and the stack trace: the ASSERT
# label (which case), then either an [exception]/[failure] line or Expected/Received. Keep those,
# drop the trace — a bare case name does not tell you what went wrong.
!cram && clean ~ /^ *ASSERT / {
  fail_cont = 0
  line = clean; sub(/^ *ASSERT */, "", line)
  if (line ~ /expected exactly|got [0-9]+$/) {            # an Alcotest.failf message, not a label
    if (curcase != shown_case) { put("       " D "└ " curcase Z); shown_case = curcase }
    put("         " R "failed:" Z " " line); next
  }
  if (curcase != shown_case) { put("       " D "└ " curcase Z); shown_case = curcase }
  last_ran = line
  put("         " D "ran:  " Z " " line); next
}
# alcotest prints a BARE `FAIL <label>` for the check that actually failed, after the ASSERT
# lines for the checks that merely ran. That line is the answer to "what is wrong", so keep it.
# A `check`'s label arrives quoted; an `Alcotest.failf` message does not, and may run over
# several lines — those continuations are the explanation, so keep them too (see fail_cont).
!cram && clean ~ /^FAIL / {
  line = clean; sub(/^FAIL */, "", line)
  if (curcase != shown_case) { put("       " D "└ " curcase Z); shown_case = curcase }
  # A failf message is echoed once after ASSERT and again after FAIL, so its first line is
  # already on screen as the `ran:` line. Skip the repeat and let the explanation carry the
  # `failed:` marker instead.
  if (line == last_ran) { fail_cont = 1; next }
  put("         " R "failed:" Z " " line); fail_cont = 1; next
}
# ...and any line back at column 0 ends it (the stack frames, alcotest's own notes, or the next
# thing entirely). No `next`: the line still gets its own rule below.
!cram && fail_cont && clean ~ /^[^ ]/ { fail_cont = 0 }
# The indented remainder of a multi-line failf message. Stack frames and alcotest's own notes
# start at column 0, so the indent alone separates them.
!cram && fail_cont && clean ~ /^  +[^ ]/ {
  line = clean; sub(/^ */, "", line)
  put("                " line)      # aligned under the text of the `ran:` line above
  next
}
!cram && clean ~ /^\[(exception|failure)\]/ {
  fail_cont = 0
  line = clean; sub(/^\[[a-z]*\] */, "", line)
  trace_left = (clean ~ /^\[exception\]/ ? 2 : 0)
  # An unwritten hole is not this case being wrong, and it reads the same whichever runner met
  # it: give it the wording the cram side gives it, and drop the frames — the hole IS the answer.
  if (line ~ /TODO\([^)]*\)/) {
    alctodo[cur] = 1; trace_left = 0
    match(line, /TODO\([^)]*\)[^"]*/)
    put("         " D "blocked by an unwritten hole: " substr(line, RSTART, RLENGTH) Z); next
  }
  put("         " R "error:" Z " " line); next
}
# Keep the first two compiler frames after an unexpected exception. Alcotest's full trace is
# noisy, but the helper that raised and its caller answer where a bare Not_found came from.
!cram && trace_left > 0 && clean ~ /^ *Called from / {
  if (clean !~ /Stdlib__|Alcotest|Dune__/) {
    line = clean
    sub(/^ *Called from /, "", line)
    put("         " D "at:   " line Z)
    trace_left--
  }
  next
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
    # a `timeout N` guard reports 124 — say so, or the learner reads a bare exit code
    for (i = 1; i <= ng; i++)
      g = g "           " (got[i] == "[124]" \
            ? "[124]   (timed out — the command never finished; an unterminated loop?)" \
            : got[i]) "\n"
    if (w != g) {
      key = cur SUBSEP pendblk; bad[key] = 1
      # The skeleton's own failwith, not a wrong answer. Keep the message: the hole that raised
      # is often NOT the one this case is about (a `check` that dies in a later hole loses the
      # diagnostics an earlier one correctly produced), and naming it is the difference between
      # "my code is wrong" and "something after it is unwritten".
      if (match(g, /TODO\([^)]*\)[^"]*/)) { todo[key] = 1; todotext[key] = substr(g, RSTART, RLENGTH) }
      detail[key] = detail[key] "         " G "the test wants:" Z "\n" \
                    (w == "" ? "           (nothing)\n" : w) \
                    "         " R "your code printed:" Z "\n" \
                    (g == "" ? "           (nothing)\n" : g)
    }
  }
  nw = 0; ng = 0; split("", want); split("", got)
}

cram && /^(diff --git|index |--- |\+\+\+ )/ { next }
# a hunk header names the .t line it starts at; walking old-file lines from there tells which
# command a `-`/`+` line belongs to even when the `$` line itself is outside the hunk's context
cram && /^@@ / { flush(); match($0, /-[0-9]+/); dline = substr($0, RSTART + 1, RLENGTH - 1) + 0; pendblk = ""; next }
cram && /^[[:space:]]+\$ / { flush(); sub(/^[[:space:]]+/, ""); pendblk = cmdblk[tfile, $0]; dline++; next }
# A `>` line continues the COMMAND, it is not output. Counting it as both wanted and produced
# put the whole shell script in each block and buried the one line that differed underneath it.
cram && /^[[:space:]]+> / { dline++; next }
# Strip the diff marker and the cram body's two-space indent, and NO MORE: eating the rest of the
# leading space made a whitespace-only difference compare equal, so a test dune had failed was
# reported PASS. Emitted IR is indented, so that is a difference worth seeing.
cram && /^-/  { if (pendblk == "") pendblk = lineblk[tfile, dline]; sub(/^-/, ""); sub(/^  /, ""); want[++nw] = $0; dline++; next }
cram && /^\+/ { if (pendblk == "") pendblk = lineblk[tfile, dline - 1]; sub(/^\+/, ""); sub(/^  /, ""); got[++ng] = $0; next }
cram && substr($0, 1, 3) == "   " { if (pendblk == "") pendblk = lineblk[tfile, dline]; sub(/^   /, ""); want[++nw] = $0; got[++ng] = $0; dline++; next }
cram { dline++; next }

# ---- alcotest: it lists every case in a failing suite, [FAIL] and [OK] alike -
/\[SKIP\]/ {                                            # a case that chose not to run (see the suite's note)
  line = clean; sub(/^[^[]*\[SKIP\][[:space:]]*/, "", line); sub(/[[:space:]]+$/, "", line)
  nf = split(line, a, /[[:space:]][[:space:]]+/)
  if (have_stage_groups && nf >= 1 && !(a[1] in this_stage)) next   # a later stage's group
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
  # Alcotest prints every case twice — once in the running list, once inside the failure box —
  # and truncates the description differently in the two, so dedupe on the group NAME and the
  # per-group INDEX, which are identical in both. (Truncating the whole line instead collapsed
  # every case of a group whose name was long enough to fill the prefix.)
  key = (nf >= 2 ? a[1] SUBSEP a[2] : line)
  # A group reporting itself "skipped — … not started" is OPTIONAL work (a §6 exercise), not a
  # pass: show it as TODO so it stays visible, and keep it out of both counts.
  if (line ~ / — skipped/) {
    sub(/ — skipped.*$/, "", line)
    if (!seen[cur SUBSEP line]++) { put("  " Y "TODO" Z " " line D " (optional)" Z); nopt[cur]++ }
    next
  }
  if (!ok) curcase = a[1]        # the box repeats this line just before the failure detail
  if (!seen[cur SUBSEP key]++) {
    if (ok) nok[cur]++; else nbad[cur]++
    if (ok && line ~ /^given:/) ngivenok[cur]++
    # a case named `given: …` checks code the learner was handed, so it says so instead of OK
    shown = line; if (ok && shown ~ /^given: */) sub(/^given: */, "", shown)
    # a failing case is a placeholder for now: whether it is WRONG or only waiting on another
    # hole is in its own log, read at the end (resolve_cases)
    put(ok ? "  " G (line ~ /^given:/ ? "GIVEN" : "OK  ") Z " " wrap_label(shown, 84) \
           : "\001" a[1] "\002" a[2] "\001" wrap_label(line, 84))
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
  # One suite now runs in several stages, so a skipped-stage roster repeats its name; a section
  # per repeat would print the same suite two or three times over.
  for (k = 1; k <= na; k++)
    if (af[k] != "" && !onroster["alcotest" SUBSEP af[k]]++)
      roster[++nrost] = "alcotest" SUBSEP af[k]
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
        # Zero passing cases does not mean untouched: an attempted implementation can make every
        # case fail or crash. Reserve TODO for output that names an explicit unfinished hole.
        waiting = 0
        if (failing && kind == "alcotest") resolve_cases(si)
        if (failing && kind == "cram") {
          unstarted = all_failed_are_todo(si, tf)
          # some cases pass and every failure is a hole elsewhere: the learner's part is done
          # as far as it can be checked, which is neither "not started" nor "wrong"
          if (!unstarted) waiting = failures_all_todo(si, tf)
        }
        # A given case may already pass (08's `given: module shape`): TODO is about whether the
        # FAILURES reached a hole, which is what CLAUDE.md's table says, not about whether
        # anything passes. Requiring zero passes turned an untouched suite into a wall of FAIL.
        else if (failing && nbad[si] > 0 && \
                 (resdir[si] != "" ? nwrong[si] == 0 : alctodo[si])) {
          if (nok[si] - ngivenok[si] > 0) waiting = 1; else unstarted = 1
        }
        total++
        if ((interrupted || (run_failed && n == 0)) && !failing) {
          why = (interrupted ? "test run interrupted" : "test runner stopped before results")
          out = out sprintf("%sSKIP%s %s (%s) — %s\n", D, Z, part[2], kind, why)
          nskip++; continue
        } else if (kind == "cram" && part[2] in explicitly_skipped && !si) {
          out = out sprintf("%sSKIP%s %s (%s) — an earlier stage failed\n", D, Z, part[2], kind)
          nskip++; continue
        } else if (kind == "alcotest" && part[2] in explicitly_skipped_alcotest && !si) {
          out = out sprintf("%sSKIP%s %s (%s) — an earlier stage failed\n", D, Z, part[2], kind)
          nskip++; continue
        } else if (optional) {
          out = out sprintf("%s%sTODO%s %s%s%s (%s) — optional\n", B, Y, Z, B, part[2], Z, kind)
          nopts++
        } else if (unstarted && !detail_all) {
          out = out sprintf("%s%sTODO%s %s%s%s (%s) — not started\n", B, Y, Z, B, part[2], Z, kind)
          ntodo++
        } else if (waiting && !detail_all) {
          out = out sprintf("%s%sWAIT%s %s%s%s (%s) — what can run passes; the rest waits on another hole\n",
                            B, Y, Z, B, part[2], Z, kind)
          nwait++
        } else if (failing) {
          out = out sprintf("%s%sFAIL%s %s%s%s (%s)\n", B, R, Z, B, part[2], Z, kind); nfail++
        } else if (blocked) {
          out = out sprintf("%sSKIP%s %s (%s)\n", D, Z, part[2], kind); nskip++; continue
        } else if (kind == "alcotest" && part[2] ~ /^harness-/) {
          # a suite that tests the test harness, not the learner's code: green from the start,
          # so it is shown as GIVEN and kept out of the passing count — it is not progress
          out = out sprintf("%sGIVEN%s %s (%s) — tests the test tools, not your code\n", G, Z,
                            part[2], kind); ngiven++; good++
        } else {
          out = out sprintf("%sPASS%s %s (%s)\n", G, Z, part[2], kind); npass++; good++
        }
        if (kind == "cram") out = out cases_str(si, tf, unstarted, waiting)
        else if (si) {
          b2 = body[si]
          # An untouched suite fails every case at an explicit TODO, and alcotest reports the
          # detail of only the first — dangling under the last case, where it reads as if it
          # belonged to it.
          # List what the suite will check, then say once why nothing runs yet.
          if ((unstarted || waiting) && !detail_all) {
            gsub(/  \033\[31mFAIL\033\[0m |  FAIL /, (waiting ? "  " Y "WAIT" Z " " : "  " D "·" Z "    "), b2)
            why = ""
            n2 = split(b2, bl, "\n"); b2 = ""
            for (li = 1; li <= n2; li++) {
              if (bl[li] ~ /^ *(\033\[[0-9;]*m)?(error|failed):/) {
                if (why == "") { why = bl[li]; sub(/^ *(\033\[[0-9;]*m)?(error|failed):(\033\[0m)? */, "", why) }
                continue
              }
              # the hole the first failure reached: said once at the end, not under a case
              if (bl[li] ~ /blocked by an unwritten hole: /) {
                if (why == "") { why = bl[li]; sub(/^.*blocked by an unwritten hole: /, "", why); sub(/\033\[0m$/, "", why) }
                continue
              }
              if (bl[li] ~ /^ *(Expected|Received):/ || bl[li] ~ /^ *└ /) continue
              if (bl[li] != "" || li < n2) b2 = b2 bl[li] "\n"
            }
            if (why != "")
              b2 = b2 "       " D (nok[si] > 0 ? "the rest waits for an unwritten hole — " \
                                                : "nothing here passes yet — ") why Z "\n"
          }
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

  tail = (ntodo ? sprintf(", %d not started", ntodo) : "") (nwait ? sprintf(", %d waiting on another hole", nwait) : "") (nopts ? sprintf(", %d optional", nopts) : "") (nskip ? sprintf(", %d not run", nskip) : "") \
         (ngiven ? sprintf(" (%d given check%s OK)", ngiven, ngiven > 1 ? "s" : "") : "")
  if (nfail || ntodo || nwait) printf "\n%s%d passing, %d failing%s%s\n", B, npass, nfail, tail, Z
  else if (npass || ngiven) printf "\n%s%d passing, 0 failing%s%s\n", G, npass, tail, Z
  else printf "\n%sno tests ran%s\n", B, Z
}

# Read each failing alcotest case's own log: a case that reached a TODO(NN) is waiting on a
# hole, not wrong. Counts the cases that are really wrong into nwrong[si], then rewrites the
# placeholders: when nothing is really wrong the suite's own WAIT/TODO pass relabels them, so
# they keep the plain FAIL text it expects; otherwise each says WAIT or FAIL for itself.
function resolve_cases(si,   pass, n, i, ln, m, g, x, f, l, hit, out, istodo) {
  nwrong[si] = 0
  for (pass = 1; pass <= 2; pass++) {
    n = split(body[si], ln, "\n"); out = ""
    for (i = 1; i <= n; i++) {
      if (match(ln[i], /^\001[^\002]*\002[0-9]+\001/)) {
        m = substr(ln[i], 2, RLENGTH - 2); split(m, x, "\002")
        f = resdir[si] "/" x[1] "." sprintf("%03d", x[2]) ".output"
        hit = 0
        if (resdir[si] != "") { while ((getline l < f) > 0) if (l ~ /TODO\([^)]*\)/) hit = 1; close(f) }
        istodo[i] = hit
        if (pass == 1) { if (!hit) nwrong[si]++; out = out ln[i]; }
        else if (nwrong[si] == 0 || !hit)
          out = out "  " R "FAIL" Z " " substr(ln[i], RLENGTH + 1)
        else out = out "  " Y "WAIT" Z " " substr(ln[i], RLENGTH + 1)
      } else out = out ln[i]
      if (i < n) out = out "\n"
    }
    if (pass == 2) body[si] = out
  }
}

function failedcram(si,   b, f) {                        # any case in this .t with a diff?
  for (b in bad) { split(b, p2, SUBSEP); if (p2[1] == si) return 1 }
  return 0
}
function nfailing(si, file,   b, c) {
  for (b = 1; b <= nblk[file]; b++) if (si SUBSEP b in bad) c++
  return c
}
# Some case failed, and every one that did reached an explicit TODO(NN).
function failures_all_todo(si, file,   b, key, n) {
  for (b = 1; b <= nblk[file]; b++) {
    key = si SUBSEP b
    if (key in bad) { if (!(key in todo)) return 0; n++ }
  }
  return n > 0
}
# Every case failed specifically because it reached an explicit TODO(NN).
function all_failed_are_todo(si, file,   b, key) {
  if (nblk[file] == 0 || nfailing(si, file) != nblk[file]) return 0
  for (b = 1; b <= nblk[file]; b++) {
    key = si SUBSEP b
    if ((key in bad) && !(key in todo)) return 0
  }
  return 1
}
# One OK/FAIL line per case, in file order. For an explicit untouched TODO, the repeated diffs
# are noise — list what the file will check and leave it at that (DETAIL=1 expands).
function cases_str(si, file, unstarted, waiting,   b, key, out, nsl, sl, i) {
  load_t(file)
  unstarted = unstarted && !detail_all
  for (b = 1; b <= nblk[file]; b++) {
    key = si SUBSEP b
    if (si && (key in bad)) {
      if (unstarted) { out = out sprintf("  %s·%s   %s\n", D, Z, wrap_label(label[file, b], 84)); continue }
      # a case that stopped at an unwritten TODO(NN) is waiting, whatever its neighbours did: one
      # real failure in the file used to turn every waiting case into FAIL
      if ((key in todo) && !detail_all)
        out = out sprintf("  %sWAIT%s %s\n", Y, Z, wrap_label(label[file, b], 84))
      else
        out = out sprintf("  %sFAIL%s %s\n", R, Z, wrap_label(label[file, b], 84))
      if (key in todo)
        out = out sprintf("         %sblocked by an unwritten hole: %s%s\n", D, todotext[key], Z)
      else {
        if ((file SUBSEP b) in srcblk && srcblk[file, b] != "") {
          out = out sprintf("         %sthe program under test%s:%s\n", C,
                            (srcname[file, b] != "" ? " (" srcname[file, b] ")" : ""), Z)
          nsl = split(srcblk[file, b], sl, "\n")
          # A handful of programs run to ~25 lines; past a screenful the report stops being
          # scannable and the .t is one `cat` away, so show the head and say what was cut.
          for (i = 1; i <= nsl && i <= 16; i++)
            out = out sprintf("           %s%s%s\n", D, sl[i], Z)
          if (nsl > 16)
            out = out sprintf("           %s… %d more lines%s\n", D, nsl - 16, Z)
        }
        out = out detail[key]
      }
    } else out = out sprintf("  %sOK  %s %s\n", G, Z, wrap_label(label[file, b], 84))
  }
  if (unstarted) out = out sprintf("       %snothing here passes yet — DETAIL=1 to see the diffs%s\n", D, Z)
  return out
}
