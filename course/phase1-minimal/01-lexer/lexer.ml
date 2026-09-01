(* The lexer: turn a source string into a stream of [Token.t].

   Hand-written (char cursor + token DFA), mirroring:
     swift/lib/Parse/Lexer.cpp     (Lexer::lexImpl and friends)

   >>> You build this in concept  phase1-minimal/01-lexer. <<<
   The token type (token.ml) is the contract; here you produce it. [tokenize] is
   provided (it just drives [next]); the lesson is implementing [next]. *)

type t = {
  src : string;
  len : int;
  mutable pos : int; (* byte offset of the next unread char *)
  mutable line : int;
  mutable col : int;
  diags : Diagnostics.sink; (* where errors go — see [error] below *)
}

let create (src : string) (diags : Diagnostics.sink) : t =
  { src; len = String.length src; pos = 0; line = 1; col = 1; diags }

(* --- small cursor helpers you'll want (already written) --------------------- *)

let here (lx : t) : Token.pos = { Token.line = lx.line; col = lx.col; offset = lx.pos }
let at_end (lx : t) : bool = lx.pos >= lx.len
let peek_char (lx : t) : char = if at_end lx then '\000' else lx.src.[lx.pos]

(* Advance one char, maintaining line/col. Returns the consumed char. *)
let bump (lx : t) : char =
  let c = lx.src.[lx.pos] in
  lx.pos <- lx.pos + 1;
  (if c = '\n' then (
     lx.line <- lx.line + 1;
     lx.col <- 1)
   else lx.col <- lx.col + 1);
  c

let make (lo : Token.pos) (lx : t) (kind : Token.kind) : Token.t =
  { Token.kind; span = { Token.lo; hi = here lx } }

(* Report an error at [lo .. here], then KEEP LEXING. Mirrors `Lexer::diagnose` in
   swift/lib/Parse/Lexer.cpp (its `Lexer` takes a `DiagnosticEngine *` for exactly this;
   Lexer.cpp calls `diagnose` in 59 places). Recovery is the point: one run should report
   every bad byte in the file, not die on the first. *)
let error (lx : t) (lo : Token.pos) (msg : string) : unit =
  Diagnostics.error lx.diags { Token.lo; hi = here lx } msg

(* --- the part you implement ------------------------------------------------- *)

(* Produce the next token. The scanning DFA, in order:
     1. skip whitespace that is NOT a newline (newlines are significant tokens);
     2. skip // line comments and /* ... */ block comments (block comments nest in Swift);
     3. if at end of input, return [Eof];
     4. otherwise dispatch on [peek_char lx]:
          - digit            -> scan an integer literal      (Token.Int)
          - letter or '_'    -> scan an identifier, then     (Token.keyword_or_ident)
          - '+' '-' '*' '/' '%' '=' '(' ')' ',' -> single-char operator/punct tokens
          - '\n'             -> Token.Newline
     Use [here lx] to capture the start position, [bump]/[peek_char]/[at_end] to scan,
     and [make lo lx kind] to build the token with its span.
   Tips: scan the lexeme into a substring with String.sub; convert with int_of_string.
   See the explainer (§3 "Build it") for the full walk-through. *)

let is_digit c = 
  match c with 
  | '0'..'9' -> true
  | _ -> false
let is_head_ident c = 
  match c with 
  | 'a'..'z' | 'A'..'Z' | '_' -> true 
  | _ -> false
let is_cont_ident c =
  is_digit c || is_head_ident c

let rec next (lx : t) : Token.t =
  (* ignore (here, make, bump, peek_char, at_end, lx);
  failwith "TODO(01-lexer): implement Lexer.next (the scanning DFA)" *)
  let take_while pred =
    while (not (at_end lx)) && pred (peek_char lx) do ignore (bump lx) done
  in
  let block_comment (opener : Token.pos) =
    let depth = ref 1 in
    while !depth > 0 && not (at_end lx) do
      match bump lx with
      | '/' when peek_char lx = '*' -> ignore (bump lx); incr depth
      | '*' when peek_char lx = '/' -> ignore (bump lx); decr depth
      | _ -> ()
    done;
    if !depth > 0 then begin
      error lx (here lx) "unterminated '/*' comment";      
      Diagnostics.emit lx.diags
        { Diagnostics.severity = Note;
          span = { Token.lo = opener; hi = here lx };
          message = "comment started here" };
      let message = 
        let missing = 
          List.init !depth (fun _ -> "*/")
          |> String.concat ""
        in 
        if !depth = 1 then
          Printf.sprintf "insert '%s' to close this comment" missing
        else
          Printf.sprintf "insert '%s' to close these %d nested comments" missing !depth
      in
      Diagnostics.emit lx.diags
        { Diagnostics.severity = Note;
          span = { Token.lo = opener; hi = here lx };
          message }
    end
  in
  (* let rec block_comment lo = 
    let check_eof () =
      if at_end lx then begin
        (* failwith (Printf.sprintf "unterminated comment at %d:%d" lo.Token.line lo.Token.col); *)
        error lx (here lx) "unterminated '/*' comment";        
        Diagnostics.emit lx.diags
          { Diagnostics.severity = Note; 
            span = { lo; hi = here lx }; 
            message = "comment started here" };
          raise Exit
      end
    in
    let rec loop () =
      take_while (fun x -> not @@ List.mem x ['*'; '/']);
      check_eof ();
      let lo = here lx in
      if bump lx = '*' then begin
        take_while ((=) '*');
        check_eof ();
        if bump lx <> '/' then loop ()          
      end else begin
        take_while ((=) '/');
        check_eof ();
        if bump lx = '*' then block_comment lo;
        loop ()
      end
    in
    try
      loop ()
    with Exit -> ()
  in *)
  let lo = here lx in
  let lexeme_from () =
    String.sub lx.src lo.Token.offset (lx.pos - lo.Token.offset)
  in
  if at_end lx then make lo lx Token.Eof
  else match bump lx with
  | ' ' | '\t' | '\r' -> next lx
  | '\n' -> make lo lx Token.Newline
  | '+' -> make lo lx Token.Plus
  | '-' -> make lo lx Token.Minus
  | '*' -> make lo lx Token.Star
  | '/' -> begin 
    if peek_char lx = '/' then begin
      take_while ((<>) '\n');
      next lx
    end else if peek_char lx = '*' then begin
      ignore (bump lx);
      block_comment lo;
      next lx 
    end else make lo lx Token.Slash
  end
  | '%' -> make lo lx Token.Percent
  | '=' -> make lo lx Token.Eq
  | '(' -> make lo lx Token.LParen
  | ')' -> make lo lx Token.RParen
  | ',' -> make lo lx Token.Comma
  | c when is_digit c -> begin
    take_while (fun c -> is_digit c || c = '_');
    let i = lexeme_from () |> int_of_string in 
    make lo lx (Token.Int i)
  end
  | c when is_head_ident c -> begin
    take_while is_cont_ident;
    lexeme_from ()
    |> Token.keyword_or_ident
    |> make lo lx
  end
  | _ -> begin 
    error lx lo "invalid character in source file";
    next lx
  end
    (* failwith (Printf.sprintf "lex error %d:%d: unexpected character %C" lx.line lx.col c)  *)
(* Drive [next] to the end. Provided — you only implement [next]. *)
let tokenize (lx : t) : Token.t list =
  let rec loop acc =
    let tok = next lx in
    match tok.Token.kind with Token.Eof -> List.rev (tok :: acc) | _ -> loop (tok :: acc)
  in
  loop []
