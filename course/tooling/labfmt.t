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

An unexpected Alcotest exception keeps the first compiler frames but drops the library stack.

  $ cat > exception.raw <<'EOF2'
  > Testing `structs'.
  > > [FAIL]        irgen-structs                0   insertvalue construction.
  > [exception] Not_found
  >             Raised at Stdlib__Hashtbl.find in file "hashtbl.ml", line 584
  >             Called from Stdlib__List.iter in file "list.ml", line 114
  >             Called from Irgen.emit_llvm.lookup_operand in file "irgen.ml", line 62
  >             Called from Irgen.emit_llvm.gen_instruction in file "irgen.ml", line 191
  >             Called from Alcotest_engine__Core.protect_test in file "core.ml", line 186
  > EOF2
  $ awk -v alcotest_suites='structs' -f labfmt.awk exception.raw | sed '/^$/d'
  ── structs: 0 of 1 passing
  FAIL structs (alcotest)
    FAIL irgen-structs — insertvalue construction
           error: Not_found
           at:   Irgen.emit_llvm.lookup_operand in file "irgen.ml", line 62
           at:   Irgen.emit_llvm.gen_instruction in file "irgen.ml", line 191
  0 passing, 1 failing
