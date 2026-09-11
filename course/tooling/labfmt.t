The compact TODO display is reserved for an explicit unwritten hole.  If every case fails
because attempted code crashes, the normal report includes the failure immediately.

  $ mkdir -p concept/tests
  $ cat > concept/tests/sample.t <<'EOF'
  > A started case reports its error.
  >   $ ./lab.exe
  > EOF
  $ cat > started.raw <<'EOF'
  > File "concept/tests/sample.t", line 1, characters 0-0:
  > diff --git a/x b/y
  > --- a/x
  > +++ b/y
  > @@ -1,2 +1,4 @@
  >  A started case reports its error.
  >    $ ./lab.exe
  > +  Fatal error: exception Not_found
  > +  [2]
  > EOF
  $ awk -v prefix=concept/ -v cram_files='tests/sample.t' -f labfmt.awk started.raw | sed '/^$/d'
  ── sample: 0 of 1 passing
  FAIL tests/sample.t (cram)
    FAIL A started case reports its error
           the test wants:
             (nothing)
           your code printed:
             Fatal error: exception Not_found
             [2]
  0 passing, 1 failing

An explicit TODO still gets the short roster, because its repeated diffs contain no useful
feedback about a learner's implementation.

  $ sed 's/Fatal error: exception Not_found/Fatal error: exception Failure("TODO(10f): implement")/' started.raw > untouched.raw
  $ awk -v prefix=concept/ -v cram_files='tests/sample.t' -f labfmt.awk untouched.raw | sed '/^$/d'
  ── sample: 0 of 1 passing
  TODO tests/sample.t (cram) — not started
    ·   A started case reports its error
         nothing here passes yet — DETAIL=1 to see the diffs
  0 passing, 0 failing, 1 not started
