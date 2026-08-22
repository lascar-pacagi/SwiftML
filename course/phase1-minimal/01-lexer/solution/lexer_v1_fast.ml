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

type soup = { tags : int array; starts : int array; ends : int array; n : int; src : string }

let is_digit c = c >= '0' && c <= '9'
let is_ident_head c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let is_ident_cont c = is_ident_head c || is_digit c

(* --- lazy line/column, only ever needed by a DIAGNOSTIC ---------------------
   Hoisted above the scanner because the error path below is its only caller in the hot
   pass: no token pays for a position, but a complaint about one can still be precise.
   That is swiftc's SourceLoc/SourceManager split, and why `lex` takes a sink. *)

let line_starts (src : string) : int array =
  let acc = ref [ 0 ] in
  String.iteri (fun i c -> if c = '\n' then acc := (i + 1) :: !acc) src;
  Array.of_list (List.rev !acc)

let pos_of (ls : int array) (off : int) : Token.pos =
  let lo = ref 0 and hi = ref (Array.length ls - 1) in
  while !lo < !hi do
    let mid = (!lo + !hi + 1) / 2 in
    if ls.(mid) <= off then lo := mid else hi := mid - 1
  done;
  { Token.line = !lo + 1; col = off - ls.(!lo) + 1; offset = off }


(* The single scanning pass: offsets only, no line/col, near-zero per-token allocation. *)
let lex (src : string) (diags : Diagnostics.sink) : soup =
  let ls = lazy (line_starts src) in
  let error (lo : int) (hi : int) (msg : string) =
    Diagnostics.error diags
      { Token.lo = pos_of (Lazy.force ls) lo; hi = pos_of (Lazy.force ls) hi }
      msg
  in
  let note (lo : int) (hi : int) (msg : string) =
    Diagnostics.emit diags
      { Diagnostics.severity = Note;
        span = { Token.lo = pos_of (Lazy.force ls) lo; hi = pos_of (Lazy.force ls) hi };
        message = msg }
  in
  let len = String.length src in
  let cap = ref (max 16 (len / 4)) in
  let tags = ref (Array.make !cap 0) in
  let starts = ref (Array.make !cap 0) in
  let ends = ref (Array.make !cap 0) in
  let n = ref 0 in
  let push tag s e =
    if !n >= !cap then (
      let nc = !cap * 2 in
      let grow a =
        let b = Array.make nc 0 in
        Array.blit a 0 b 0 !cap;
        b
      in
      tags := grow !tags;
      starts := grow !starts;
      ends := grow !ends;
      cap := nc);
    !tags.(!n) <- tag;
    !starts.(!n) <- s;
    !ends.(!n) <- e;
    incr n
  in
  let pos = ref 0 in
  let g i = String.unsafe_get src i in
  (* skip non-newline whitespace and //, /* */ comments; leave '\n' (it's a token) *)
  let rec skip () =
    if !pos >= len then ()
    else
      let c = g !pos in
      if c = ' ' || c = '\t' || c = '\r' then (
        incr pos;
        while !pos < len && (let d = g !pos in d = ' ' || d = '\t' || d = '\r') do incr pos done;
        skip ())
      else if c = '/' && !pos + 1 < len && g (!pos + 1) = '/' then (
        pos := !pos + 2;
        while !pos < len && g !pos <> '\n' do incr pos done;
        skip ())
      else if c = '/' && !pos + 1 < len && g (!pos + 1) = '*' then (
        let opener = !pos in
        pos := !pos + 2;
        let depth = ref 1 in
        while !depth > 0 && !pos < len do
          if g !pos = '/' && !pos + 1 < len && g (!pos + 1) = '*' then (pos := !pos + 2; incr depth)
          else if g !pos = '*' && !pos + 1 < len && g (!pos + 1) = '/' then (pos := !pos + 2; decr depth)
          else incr pos
        done;
        (* Unterminated: the same three diagnostics v0 produces once §6 exercise 2 is done —
           the error at end of input, a note at the OUTERMOST opener, and the repair. The two
           rungs must agree about what is NOT lexable, not only about what is. Note how much
           cheaper positions are here: the scan carried plain offsets, and `pos_of` turns them
           into line/col only now, because someone finally asked. *)
        if !depth > 0 then (
          error !pos !pos "unterminated '/*' comment";
          note opener (opener + 2) "comment started here";
          let terminator = String.concat "" (List.init !depth (fun _ -> "*/")) in
          note !pos !pos
            (if !depth = 1 then Printf.sprintf "insert '%s' to close this comment" terminator
             else Printf.sprintf "insert '%s' to close these %d nested comments" terminator !depth));
        skip ())
      else ()
  in
  let continue = ref true in
  while !continue do
    skip ();
    if !pos >= len then (
      push t_eof len len;
      continue := false)
    else
      let s = !pos in
      let c = g !pos in
      if is_digit c then (
        incr pos;
        while !pos < len && is_digit (g !pos) do incr pos done;
        push t_int s !pos)
      else if is_ident_head c then (
        incr pos;
        while !pos < len && is_ident_cont (g !pos) do incr pos done;
        push t_ident s !pos)
      else (
        let tag =
          match c with
          | '+' -> t_plus | '-' -> t_minus | '*' -> t_star | '/' -> t_slash | '%' -> t_percent
          | '=' -> t_eq | '(' -> t_lparen | ')' -> t_rparen | ',' -> t_comma | '\n' -> t_newline
          | _ -> -1
        in
        incr pos;
        if tag < 0 then error s !pos "invalid character in source file" else push tag s !pos)
  done;
  { tags = !tags; starts = !starts; ends = !ends; n = !n; src }

(* resolve a keyword without allocating a substring *)
let kw_or_ident (src : string) (s : int) (e : int) : Token.kind =
  let n = e - s in
  let eq3 a b c = n = 3 && src.[s] = a && src.[s + 1] = b && src.[s + 2] = c in
  if eq3 'l' 'e' 't' then Token.Kw_let
  else if eq3 'v' 'a' 'r' then Token.Kw_var
  else Token.Ident (String.sub src s n)

let kind_of (s : soup) (i : int) : Token.kind =
  match s.tags.(i) with
  | 0 -> Token.Int (int_of_string (String.sub s.src s.starts.(i) (s.ends.(i) - s.starts.(i))))
  | 1 -> kw_or_ident s.src s.starts.(i) s.ends.(i)
  | 2 -> Token.Plus | 3 -> Token.Minus | 4 -> Token.Star | 5 -> Token.Slash | 6 -> Token.Percent
  | 7 -> Token.Eq | 8 -> Token.LParen | 9 -> Token.RParen | 10 -> Token.Comma | 11 -> Token.Newline
  | _ -> Token.Eof

(* Rebuild the exact Token.t list v0 produces — kinds + line/col spans. On demand. *)
let to_tokens (s : soup) : Token.t list =
  let ls = line_starts s.src in
  let rec build i acc =
    if i < 0 then acc
    else
      let tok =
        {
          Token.kind = kind_of s i;
          span = { Token.lo = pos_of ls s.starts.(i); hi = pos_of ls s.ends.(i) };
        }
      in
      build (i - 1) (tok :: acc)
  in
  build (s.n - 1) []
