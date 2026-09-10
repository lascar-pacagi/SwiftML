(* FAST lexer rung (`v1_fast`) for the concept-01 throughput bench.

   The reference `Lexer` (v0) is allocation-bound: every token is four heap records
   (the token, its `span`, and two `pos`es with line/col/offset), so building ~750k
   tokens dominates the cost — the actual character scanning is a rounding error.

   v1_fast does what swiftc's lexer does to go fast:
     1. **Offset-only positions.** A token records just two byte offsets (start, end).
        Line/column are NOT tracked in the hot loop; they're computed *lazily* from a
        one-time line-start table only when something (a diagnostic) actually needs them
        — exactly Swift's `SourceLoc` + `SourceManager` design.
     2. **Struct-of-arrays "token soup".** Tokens go into three parallel growable arrays
        (tag, start, end) — no per-token record, no per-token `span`/`pos` allocation.
        Constant token kinds are unboxed ints; literal values and identifier strings are
        left as offset ranges and resolved on demand.
   The hot loop therefore allocates essentially nothing per token. `to_tokens` rebuilds
   the exact `Token.t list` (kinds + line/col spans) on demand, so we can prove the fast
   path is equivalent to v0. *)

(* token-kind tags (constant kinds become ints; Int/Ident keep an offset range) *)
let t_int = 0
let t_ident = 1
let t_plus = 2
let t_minus = 3
let t_star = 4
let t_slash = 5
let t_percent = 6
let t_eq = 7
let t_lparen = 8
let t_rparen = 9
let t_comma = 10
let t_newline = 11
let t_eof = 12

type soup = { tags : int array; starts : int array; ends : int array; n : int; source : string }

let is_digit c = c >= '0' && c <= '9'
let is_identifier_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let is_identifier_continue c = is_identifier_start c || is_digit c

(* --- lazy line/column, only ever needed by a DIAGNOSTIC ---------------------
   Hoisted above the scanner because the error path below is its only caller in the hot
   pass: no token pays for a position, but a complaint about one can still be precise.
   That is swiftc's SourceLoc/SourceManager split, and why `lex` takes a sink. *)

let line_start_offsets (source : string) : int array =
  let acc = ref [ 0 ] in
  String.iteri (fun i c -> if c = '\n' then acc := (i + 1) :: !acc) source;
  Array.of_list (List.rev !acc)

let position_of_offset (ls : int array) (off : int) : Token.pos =
  let lo = ref 0 and hi = ref (Array.length ls - 1) in
  while !lo < !hi do
    let mid = (!lo + !hi + 1) / 2 in
    if ls.(mid) <= off then lo := mid else hi := mid - 1
  done;
  { Token.line = !lo + 1; col = off - ls.(!lo) + 1; offset = off }


(* The single scanning pass: offsets only, no line/col, near-zero per-token allocation. *)
let lex (source : string) (diagnostics : Diagnostics.sink) : soup =
  let ls = lazy (line_start_offsets source) in
  let report_error (lo : int) (hi : int) (msg : string) =
    Diagnostics.error diagnostics
      { Token.lo = position_of_offset (Lazy.force ls) lo; hi = position_of_offset (Lazy.force ls) hi }
      msg
  in
  let note (lo : int) (hi : int) (msg : string) =
    Diagnostics.emit diagnostics
      { Diagnostics.severity = Note;
        span = { Token.lo = position_of_offset (Lazy.force ls) lo; hi = position_of_offset (Lazy.force ls) hi };
        message = msg }
  in
  let source_length = String.length source in
  let capacity = ref (max 16 (source_length / 4)) in
  let tags = ref (Array.make !capacity 0) in
  let starts = ref (Array.make !capacity 0) in
  let ends = ref (Array.make !capacity 0) in
  let n = ref 0 in
  let push tag s e =
    if !n >= !capacity then (
      let nc = !capacity * 2 in
      let grow a =
        let b = Array.make nc 0 in
        Array.blit a 0 b 0 !capacity;
        b
      in
      tags := grow !tags;
      starts := grow !starts;
      ends := grow !ends;
      capacity := nc);
    !tags.(!n) <- tag;
    !starts.(!n) <- s;
    !ends.(!n) <- e;
    incr n
  in
  let pos = ref 0 in
  let char_at i = String.unsafe_get source i in
  (* skip_trivia non-newline whitespace and //, /* */ comments; leave '\n' (it's a token) *)
  let rec skip_trivia () =
    if !pos >= source_length then ()
    else
      let c = char_at !pos in
      if c = ' ' || c = '\t' || c = '\r' then (
        incr pos;
        while !pos < source_length && (let d = char_at !pos in d = ' ' || d = '\t' || d = '\r') do incr pos done;
        skip_trivia ())
      else if c = '/' && !pos + 1 < source_length && char_at (!pos + 1) = '/' then (
        pos := !pos + 2;
        while !pos < source_length && char_at !pos <> '\n' do incr pos done;
        skip_trivia ())
      else if c = '/' && !pos + 1 < source_length && char_at (!pos + 1) = '*' then (
        let opener = !pos in
        pos := !pos + 2;
        let depth = ref 1 in
        while !depth > 0 && !pos < source_length do
          if char_at !pos = '/' && !pos + 1 < source_length && char_at (!pos + 1) = '*' then (pos := !pos + 2; incr depth)
          else if char_at !pos = '*' && !pos + 1 < source_length && char_at (!pos + 1) = '/' then (pos := !pos + 2; decr depth)
          else incr pos
        done;
        (* Unterminated: the same three diagnostics v0 produces once §6 exercise 2 is done —
           the error at end of input, a note at the OUTERMOST opener, and the repair. The two
           rungs must agree about what is NOT lexable, not only about what is. Note how much
           cheaper positions are here: the scan carried plain offsets, and `position_of_offset` turns them
           into line/col only now, because someone finally asked. *)
        if !depth > 0 then (
          report_error !pos !pos "unterminated '/*' comment";
          note opener (opener + 2) "comment started here";
          let terminator = String.concat "" (List.init !depth (fun _ -> "*/")) in
          note !pos !pos
            (if !depth = 1 then Printf.sprintf "insert '%s' to close this comment" terminator
             else Printf.sprintf "insert '%s' to close these %d nested comments" terminator !depth));
        skip_trivia ())
      else ()
  in
  let continue = ref true in
  while !continue do
    skip_trivia ();
    if !pos >= source_length then (
      push t_eof source_length source_length;
      continue := false)
    else
      let s = !pos in
      let c = char_at !pos in
      if is_digit c then (
        incr pos;
        while !pos < source_length && is_digit (char_at !pos) do incr pos done;
        push t_int s !pos)
      else if is_identifier_start c then (
        incr pos;
        while !pos < source_length && is_identifier_continue (char_at !pos) do incr pos done;
        push t_ident s !pos)
      else (
        let tag =
          match c with
          | '+' -> t_plus | '-' -> t_minus | '*' -> t_star | '/' -> t_slash | '%' -> t_percent
          | '=' -> t_eq | '(' -> t_lparen | ')' -> t_rparen | ',' -> t_comma | '\n' -> t_newline
          | _ -> -1
        in
        incr pos;
        if tag < 0 then report_error s !pos "invalid character in source file" else push tag s !pos)
  done;
  { tags = !tags; starts = !starts; ends = !ends; n = !n; source }

(* resolve a keyword without allocating a substring *)
let keyword_or_identifier (source : string) (s : int) (e : int) : Token.kind =
  let n = e - s in
  let eq3 a b c = n = 3 && source.[s] = a && source.[s + 1] = b && source.[s + 2] = c in
  if eq3 'l' 'e' 't' then Token.Kw_let
  else if eq3 'v' 'a' 'r' then Token.Kw_var
  else Token.Ident (String.sub source s n)

let token_kind_at (s : soup) (i : int) : Token.kind =
  match s.tags.(i) with
  | 0 -> Token.Int (int_of_string (String.sub s.source s.starts.(i) (s.ends.(i) - s.starts.(i))))
  | 1 -> keyword_or_identifier s.source s.starts.(i) s.ends.(i)
  | 2 -> Token.Plus | 3 -> Token.Minus | 4 -> Token.Star | 5 -> Token.Slash | 6 -> Token.Percent
  | 7 -> Token.Eq | 8 -> Token.LParen | 9 -> Token.RParen | 10 -> Token.Comma | 11 -> Token.Newline
  | _ -> Token.Eof

(* Rebuild the exact Token.t list v0 produces — kinds + line/col spans. On demand. *)
let to_tokens (s : soup) : Token.t list =
  let ls = line_start_offsets s.source in
  let rec build i acc =
    if i < 0 then acc
    else
      let tok =
        {
          Token.kind = token_kind_at s i;
          span = { Token.lo = position_of_offset ls s.starts.(i); hi = position_of_offset ls s.ends.(i) };
        }
      in
      build (i - 1) (tok :: acc)
  in
  build (s.n - 1) []
