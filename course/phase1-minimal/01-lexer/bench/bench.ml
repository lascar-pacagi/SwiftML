(* Lexer throughput benchmark (concept 01).

   Generates a few MB of representative Swift source and lexes it 20×, reporting MB/s.

   Run:  make bench C=phase1-minimal/01-lexer
   (Needs a working lexer: crashes on the `failwith` skeleton, like the tests.)

   Two rungs:
     v0_naive  the reference `Lexer` — a `Token.t list`, eager line/col (4 heap records/token).
     v1_fast   `Lexer_v1_fast` — a columnar "token soup" with offset-only positions and
               lazy line/col (swiftc's design). The hot loop allocates ~nothing per token.
   The bench first proves v1_fast rebuilds the IDENTICAL token stream (kinds + spans),
   then TIMES both and FAILS (exit 1) if the fast rung isn't meaningfully faster — that is
   the concept's perf gate (definition of done #3: vK must beat v(K-1)).

   For *where* the time goes rather than how much, see `make profile C=phase1-minimal/01-lexer`. *)

(* The gate. The real gain is ~8x; 3x leaves room for a loaded laptop but still fails
   loudly if v1 is only "a bit" faster — which means it is still allocating per token. *)
let min_speedup = 3.0

let gen_source ~lines : string =
  let b = Buffer.create (lines * 56) in
  for i = 0 to lines - 1 do
    Buffer.add_string b
      (Printf.sprintf "let value_%d = 1000 + %d * 3 - 40 / 5 %% 6   // row %d\n" i i i)
  done;
  Buffer.contents b

(* Correctness gate: v1_fast (resolved to Token.t via to_tokens) must agree with v0
   token-for-token — kinds AND line/col spans — including nesting comments, a comment
   that spans a newline, unary minus, punctuation. *)
let tricky = "let x1 = 22\n  /* a /* b */\n c */ y9 - ( 3 , 4 )\n// tail\nz\n"

let check_equiv () =
  let d = Diagnostics.create () in
  let v0 = Lexer.tokenize (Lexer.create tricky d) in
  let v1 = Lexer_v1_fast.(to_tokens (lex tricky d)) in
  if v0 = v1 then print_endline "  equivalence: v1_fast == v0_naive  (kinds + line/col spans) OK"
  else (
    print_endline "  equivalence: MISMATCH — v1_fast changed the token stream!";
    List.iteri
      (fun i (a : Token.t) ->
        match List.nth_opt v1 i with
        | Some b when a = b -> ()
        | Some b ->
            Printf.printf "    [%d] v0=%s@%d:%d  v1=%s@%d:%d\n" i (Token.string_of_kind a.Token.kind)
              a.Token.span.Token.lo.Token.line a.Token.span.Token.lo.Token.col
              (Token.string_of_kind b.Token.kind) b.Token.span.Token.lo.Token.line
              b.Token.span.Token.lo.Token.col
        | None -> Printf.printf "    [%d] v1 shorter\n" i)
      v0;
    exit 1)

let time name (count : unit -> int) (iters : int) (mb : float) : float =
  ignore (count ());
  (* warm up *)
  let t0 = Sys.time () in
  let last = ref 0 in
  for _ = 1 to iters do
    last := count ()
  done;
  let dt = Sys.time () -. t0 in
  let mbps = mb *. float_of_int iters /. dt in
  Printf.printf "  %-9s  %6.1f MB/s   (%d tokens/lex, %.3fs)\n" name mbps !last dt;
  mbps

(* v1_fast ships as a skeleton; until it is written there is nothing to compare or gate. *)
let v1_ready () =
  match Lexer_v1_fast.lex "1 + 2" (Diagnostics.create ()) with
  | _ -> true
  | exception Failure _ -> false

let () =
  let lines = 50_000 in
  let iters = 20 in
  let src = gen_source ~lines in
  let mb = float_of_int (String.length src) /. 1.0e6 in
  Printf.printf "Lexer throughput — %.2f MB source (%d lines) x %d iterations:\n" mb lines iters;
  if not (v1_ready ()) then (
    let v0 =
      time "v0_naive"
        (fun () -> List.length (Lexer.tokenize (Lexer.create src (Diagnostics.create ()))))
        iters mb
    in
    ignore v0;
    print_endline "";
    print_endline "  v1_fast is not implemented yet (TODO(01-v1a) in lexer_v1_fast.ml), so there is";
    print_endline "  nothing to compare against and the perf gate is skipped. `make profile` works";
    print_endline "  on v0 alone and shows you why the fast rung is worth writing.";
    exit 0);
  check_equiv ();
  let v0 =
    time "v0_naive"
      (fun () -> List.length (Lexer.tokenize (Lexer.create src (Diagnostics.create ()))))
      iters mb
  in
  let v1 =
    time "v1_fast"
      (fun () -> (Lexer_v1_fast.lex src (Diagnostics.create ())).Lexer_v1_fast.n)
      iters mb
  in
  Printf.printf "  => v1_fast is %.1fx v0_naive\n" (v1 /. v0);
  if v1 /. v0 < min_speedup then (
    Printf.printf
      "\n  PERF GATE FAILED: v1_fast must be at least %.1fx v0_naive, measured %.1fx.\n\
      \  A fast rung that allocates per token is not a fast rung — run\n\
      \  `make profile C=phase1-minimal/01-lexer` (section 3) and drive words/token down.\n"
      min_speedup (v1 /. v0);
    exit 1)
