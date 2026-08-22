(* Lexer PROFILE (concept 01) — `make profile C=phase1-minimal/01-lexer`.

   `make bench` answers "how fast?"; this answers "slow WHERE?". Four views, each
   attacking the question from a different side — no external profiler required:

     1. per-construct throughput   which token shape costs the most per byte
     2. the cost ladder            what each layer of the design costs (ablation)
     3. allocation accounting      words allocated per token, minor GCs, promotions
     4. allocation sites           Gc.Memprof: the source lines that allocate most

   The lexer under the microscope is the one YOU wrote (`Lexer`, from ../lexer.ml);
   `Lexer_v1_fast` is the optimized rung, used here as the reference for what the
   same work costs without per-token allocation and eager line/col.

   For a CPU sampling profile (a real call tree from macOS `sample`), see
   `make profile-cpu C=phase1-minimal/01-lexer`. *)

(* ---------- input generators: each one is dominated by ONE construct ---------- *)

(* Every source is padded to about the same byte size, so MB/s is comparable. *)
let target_bytes = 2_000_000

let repeat_to (unit_str : string) : string =
  let b = Buffer.create (target_bytes + 64) in
  while Buffer.length b < target_bytes do
    Buffer.add_string b unit_str
  done;
  Buffer.contents b

let shapes : (string * string) list =
  [
    ("identifiers", repeat_to "value_x9 ");
    ("integers", repeat_to "1234567 ");
    ("operators", repeat_to "+ - * / % = ( ) , ");
    ("whitespace", repeat_to "1        ");
    ("newlines", repeat_to "1\n");
    ("line comments", repeat_to "// a comment line\n");
    ("block comments", repeat_to "/* a block comment */ ");
    ("nested comments", repeat_to "/* a /* b */ c */ ");
    ("mixed (real code)", repeat_to "let value_9 = 1000 + 9 * 3 - 40 / 5 % 6   // row\n");
  ]

(* ---------- timing ---------- *)

let bytes_mb (s : string) = float_of_int (String.length s) /. 1.0e6

(* Best-of-3 wall time for one pass over [src]; returns (seconds, token count). *)
let best_of_3 (f : string -> int) (src : string) : float * int =
  let n = ref 0 in
  let best = ref infinity in
  for _ = 1 to 3 do
    let t0 = Unix.gettimeofday () in
    n := f src;
    let dt = Unix.gettimeofday () -. t0 in
    if dt < !best then best := dt
  done;
  (!best, !n)

(* Each measurement gets a fresh sink; on clean input nothing is ever pushed into it. *)
let count_v0 (src : string) : int =
  List.length (Lexer.tokenize (Lexer.create src (Diagnostics.create ())))

let count_v1 (src : string) : int =
  (Lexer_v1_fast.lex src (Diagnostics.create ())).Lexer_v1_fast.n

(* v1_fast ships as a skeleton (TODO(01-v1a)) — and the profile is most useful BEFORE you
   write it, since it is what motivates the rewrite. So every v1 measurement is optional. *)
let have_v1 = lazy (match count_v1 "1 + 2" with _ -> true | exception Failure _ -> false)
let with_v1 (f : unit -> 'a) : 'a option = if Lazy.force have_v1 then Some (f ()) else None

(* The floor: touch every byte, do nothing else. Nothing built on a byte cursor can
   beat this, so it is the honest ceiling for "how fast could scanning possibly be". *)
let count_floor (src : string) : int =
  let n = ref 0 in
  String.iter (fun c -> if c = ' ' then incr n) src;
  !n

(* ---------- 1. per-construct throughput ---------- *)

let section_shapes () =
  print_endline "1. WHERE THE BYTES GO — cost per construct";
  print_endline "";
  print_endline "   ns/token is the honest cross-shape comparator (MB/s also reflects how many";
  print_endline "   tokens a shape packs per byte). Comments produce no tokens — read their MB/s.";
  print_endline "";
  Printf.printf "   %-18s %10s %10s %12s %10s\n" "construct" "MB/s v0" "MB/s v1" "ns/token v0"
    "tokens";
  Printf.printf "   %s\n" (String.make 64 '-');
  let rows =
    List.map
      (fun (name, src) ->
        let mb = bytes_mb src in
        let t0, n0 = best_of_3 count_v0 src in
        let mbps0 = mb /. t0 in
        let mbps1 =
          match with_v1 (fun () -> best_of_3 count_v1 src) with
          | Some (t1, _) -> mb /. t1
          | None -> nan
        in
        let ns = t0 *. 1.0e9 /. float_of_int (max 1 n0) in
        let ns_col = if n0 < 1000 then "           -" else Printf.sprintf "%12.1f" ns in
        let v1_col = if Float.is_nan mbps1 then "         -" else Printf.sprintf "%10.1f" mbps1 in
        Printf.printf "   %-18s %10.1f %s %s %10d\n" name mbps0 v1_col ns_col n0;
        (name, mbps0, ns, n0))
      shapes
  in
  print_endline "";
  let token_rows = List.filter (fun (_, _, _, n) -> n >= 1000) rows in
  let worst =
    List.fold_left (fun a r -> if (fun (_, _, ns, _) -> ns) r > (fun (_, _, ns, _) -> ns) a then r else a)
      (List.hd token_rows) token_rows
  in
  let best =
    List.fold_left (fun a r -> if (fun (_, _, ns, _) -> ns) r < (fun (_, _, ns, _) -> ns) a then r else a)
      (List.hd token_rows) token_rows
  in
  let name_of (n, _, _, _) = n and ns_of (_, _, ns, _) = ns in
  Printf.printf "   => per token: %s is dearest (%.0f ns), %s cheapest (%.0f ns) — a %.1fx spread.\n"
    (name_of worst) (ns_of worst) (name_of best) (ns_of best)
    (ns_of worst /. ns_of best);
  print_endline "      A construct costs either because it RE-READS bytes or because it ALLOCATES.";
  print_endline "      Sections 3 and 4 say which.";
  print_endline ""

(* ---------- 2. the cost ladder ---------- *)

let section_ladder (src : string) =
  print_endline "2. THE COST LADDER — what each layer of the design costs (same input)";
  print_endline "";
  let mb = bytes_mb src in
  let tf, _ = best_of_3 count_floor src in
  let t0, n0 = best_of_3 count_v0 src in
  let row name t note =
    Printf.printf "   %-34s %8.1f MB/s  %8.2f ms   %s\n" name (mb /. t) (t *. 1000.) note
  in
  row "byte scan floor (no tokens)" tf "memory bandwidth ceiling";
  (match with_v1 (fun () -> best_of_3 count_v1 src) with
  | Some (t1, n1) -> row "v1_fast (offsets, columnar)" t1 (Printf.sprintf "%d tokens" n1)
  | None -> print_endline "   v1_fast (offsets, columnar)          -            -       not implemented yet");
  row "v0 (Token.t list + line/col)" t0 (Printf.sprintf "%d tokens" n0);
  print_endline "";
  Printf.printf "   => scanning itself is %.0f%% of v0's time; the other %.0f%% is what v0 BUILDS\n"
    (tf /. t0 *. 100.) ((t0 -. tf) /. t0 *. 100.);
  (match with_v1 (fun () -> best_of_3 count_v1 src) with
  | Some (t1, _) ->
      Printf.printf
        "      (v1_fast keeps the same scan and pays %.1fx less than v0 for the building)\n"
        ((t0 -. tf) /. (t1 -. tf))
  | None -> print_endline "      (implement TODO(01-v1a) to see what the fast rung pays instead)");
  print_endline ""

(* ---------- 3. allocation accounting ---------- *)

let words_of (f : string -> int) (src : string) : float * int * int * int =
  Gc.full_major ();
  let before = Gc.quick_stat () in
  let n = f src in
  let after = Gc.quick_stat () in
  let words =
    after.Gc.minor_words +. after.Gc.major_words -. after.Gc.promoted_words
    -. (before.Gc.minor_words +. before.Gc.major_words -. before.Gc.promoted_words)
  in
  ( words,
    n,
    after.Gc.minor_collections - before.Gc.minor_collections,
    after.Gc.major_collections - before.Gc.major_collections )

let section_alloc (src : string) =
  print_endline "3. ALLOCATION — is this compute-bound or allocation-bound?";
  print_endline "";
  Printf.printf "   %-30s %14s %12s %10s %10s\n" "" "words alloc'd" "words/token" "minor GC" "major GC";
  Printf.printf "   %s\n" (String.make 80 '-');
  let show name f =
    let w, n, minor, major = words_of f src in
    Printf.printf "   %-30s %14.0f %12.1f %10d %10d\n" name w (w /. float_of_int (max 1 n)) minor major;
    w /. float_of_int (max 1 n)
  in
  let w0 = show "v0 (Token.t list + line/col)" count_v0 in
  let w1 = with_v1 (fun () -> show "v1_fast (offsets, columnar)" count_v1) in
  print_endline "";
  (match w1 with
  | Some w1 ->
      Printf.printf "   => v0 allocates %.1f words per token, v1_fast %.1f (%.0fx less).\n" w0 w1
        (w0 /. max 0.01 w1)
  | None ->
      Printf.printf "   => v0 allocates %.1f words per token (v1_fast not implemented yet).\n" w0);
  print_endline "      One OCaml word = 8 bytes. A Token.t is a record holding a span, which holds";
  print_endline "      two positions — plus one list cons per token. That is the 4-records-per-token";
  print_endline "      shape §5 of the explainer talks about; the number above is the receipt.";
  print_endline ""

(* ---------- 4. allocation sites (Gc.Memprof) ---------- *)

(* Statistical allocation profiler: sample 1 in ~1000 words, keep a short callstack,
   and attribute the sampled words to the first frame that lives in our own code. *)
let section_memprof ?(rung = "v0") ~(run : string -> int) (src : string) =
  Printf.printf "4. ALLOCATION SITES (%s) — Gc.Memprof, sampled callstacks\n" rung;
  print_endline "";
  let tbl : (string, int) Hashtbl.t = Hashtbl.create 64 in
  let total = ref 0 in
  let attribute (cs : Printexc.raw_backtrace) (n_samples : int) =
    let slots = Option.value ~default:[||] (Printexc.backtrace_slots cs) in
    let key = ref "<unknown>" in
    (try
       Array.iter
         (fun slot ->
           match Printexc.Slot.location slot with
           | Some loc when Filename.check_suffix loc.Printexc.filename ".ml" ->
               let fn = Option.value ~default:"?" (Printexc.Slot.name slot) in
               key :=
                 Printf.sprintf "%s:%d %s" (Filename.basename loc.Printexc.filename)
                   loc.Printexc.line_number fn;
               raise Exit
           | _ -> ())
         slots
     with Exit -> ());
    total := !total + n_samples;
    Hashtbl.replace tbl !key (n_samples + Option.value ~default:0 (Hashtbl.find_opt tbl !key))
  in
  let tracker =
    {
      Gc.Memprof.null_tracker with
      alloc_minor =
        (fun (a : Gc.Memprof.allocation) ->
          attribute a.Gc.Memprof.callstack a.Gc.Memprof.n_samples;
          None);
      alloc_major =
        (fun (a : Gc.Memprof.allocation) ->
          attribute a.Gc.Memprof.callstack a.Gc.Memprof.n_samples;
          None);
    }
  in
  let h = Gc.Memprof.start ~sampling_rate:1e-3 ~callstack_size:12 tracker in
  ignore (run src);
  Gc.Memprof.stop ();
  Gc.Memprof.discard h;
  let rows = Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl [] in
  let rows = List.sort (fun (_, a) (_, b) -> compare b a) rows in
  if !total = 0 then
    print_endline "   (no samples — build with debug info, or raise the sampling rate)"
  else
    List.iteri
      (fun i (site, n) ->
        if i < 8 then
          Printf.printf "   %-40s %6.1f%%  %s\n" site
            (float_of_int n /. float_of_int !total *. 100.)
            (String.make (int_of_float (float_of_int n /. float_of_int !total *. 40.)) '#'))
      rows;
  print_endline "";
  print_endline "      Percentages are of sampled allocated words, attributed to the innermost";
  print_endline "      frame with a source location. Read it as \"this line is where the garbage";
  print_endline "      comes from\" — then ask whether that value needs to be heap-allocated.";
  print_endline ""

(* ---------- main ---------- *)

(* `--spin [seconds] [v0|v1]`: just lex, in a loop, so an external sampling profiler
   (`make profile-cpu`) has a steady single-rung workload to attach to. No Memprof, no
   equivalence check — unlike the bench, which interleaves both rungs and would split the
   samples between them. *)
let spin (seconds : float) (rung : string) =
  let src = List.assoc "mixed (real code)" shapes in
  let run = if rung = "v1" then count_v1 else count_v0 in
  let t0 = Unix.gettimeofday () in
  let n = ref 0 in
  while Unix.gettimeofday () -. t0 < seconds do
    n := run src
  done;
  Printf.printf "spun %s for %.0fs (%d tokens/pass)\n" rung seconds !n

let main () =
  let mixed = List.assoc "mixed (real code)" shapes in
  Printf.printf "Lexer profile — %.2f MB of generated Swift per measurement, best of 3.\n\n"
    (bytes_mb mixed);
  section_shapes ();
  section_ladder mixed;
  section_alloc mixed;
  section_memprof ~rung:"v0" ~run:count_v0 mixed;
  (* the same question for the fast rung: once the per-token records are gone, what is
     LEFT allocating? (the growable arrays, and the Token.t list `to_tokens` rebuilds) *)
  (match with_v1 (fun () -> ()) with
  | Some () ->
      section_memprof ~rung:"v1_fast" ~run:count_v1 mixed;
      section_memprof ~rung:"v1_fast + to_tokens"
        ~run:(fun src ->
          List.length (Lexer_v1_fast.to_tokens (Lexer_v1_fast.lex src (Diagnostics.create ()))))
        mixed
  | None -> ());
  print_endline "Next: `make profile-cpu C=phase1-minimal/01-lexer` for a sampled call tree,";
  print_endline "      and see the explainer §5 for how to read all of this."

let () =
  match Array.to_list Sys.argv with
  | _ :: "--spin" :: rest ->
      let secs = match rest with s :: _ -> float_of_string s | [] -> 8.0 in
      let rung = match rest with _ :: r :: _ -> r | _ -> "v0" in
      spin secs rung
  | _ -> main ()
