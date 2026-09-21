The frozen answer key: a verified copy of every module this concept asks the learner to edit
(only those). Header each file `(* FROZEN SOLUTION — … *)`. Verified means: with these files
swapped over the skeletons, `make lab C=<this concept>` is green AND the swiftc oracle passes.
Never edit the learner's skeleton to verify — swap, test, restore.

`exercises/` holds the same modules with §6's exercises APPLIED — one file per stage module an
exercise touches, headed `(* FROZEN SOLUTION — <concept>, WITH §6's EXERCISES APPLIED *)`, with
every difference from the stock key marked `EX<n>` in a comment. `make check-exercises C=<this
concept>` builds it and runs the concept's tests: the exercise groups in `tests/test_exercises.ml`
must all report `checked`, AND the concept's own suite must still pass with the exercises in.
It exists so the code `explainer.qmd` §9 quotes is code that compiles — §9 is written, not
produced, which is how a fold in 63-bit `int` and an evaluation order OCaml leaves unspecified
both shipped in concept 04's.
