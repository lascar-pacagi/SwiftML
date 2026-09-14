(* Diagnostics — a *contract*, carried unchanged from Phase 1. Producers
   (lexer/parser/sema) call [error]/[warning]; the driver calls [print]/[has_errors].

   Design oracle: swift/include/swift/Basic/Diagnostic*.h *)

type severity = Error | Warning | Note
type t = { severity : severity; span : Token.span; message : string }
type sink = { mutable diagnostics : t list; source : string option }

let create ?source () : sink = { diagnostics = []; source }

let emit (sink : sink) (diagnostic : t) =
  sink.diagnostics <- diagnostic :: sink.diagnostics

let error (sink : sink) (span : Token.span) (message : string) =
  emit sink { severity = Error; span; message }

let warning (sink : sink) (span : Token.span) (message : string) =
  emit sink { severity = Warning; span; message }

(* A note is not a problem in its own right: it explains the diagnostic above it, or points
   at the code that caused it (swiftc: `note: change 'let' to 'var' to make it mutable`).
   It never makes [has_errors] true. *)
let note (sink : sink) (span : Token.span) (message : string) =
  emit sink { severity = Note; span; message }

let has_errors (sink : sink) =
  List.exists (fun diagnostic -> diagnostic.severity = Error) sink.diagnostics

let all (sink : sink) : t list = List.rev sink.diagnostics

let string_of_severity = function
  | Error -> "error"
  | Warning -> "warning"
  | Note -> "note"

let to_string (diagnostic : t) : string =
  Printf.sprintf "%d:%d: %s: %s" diagnostic.span.Token.lo.Token.line
    diagnostic.span.Token.lo.Token.col
    (string_of_severity diagnostic.severity)
    diagnostic.message

(* The source line a diagnostic points at, with a caret under its column — the shape
   `swiftc -diagnostic-style=llvm` prints. The caret matters most when the span points at a
   token with no glyph: the Newline that ends a line puts it just past the text, which reads
   as "at the end of THIS line" instead of at a column that looks empty. The prefix copies the
   line's own leading characters so a tab stays a tab and the caret still lines up. *)
let snippet (source : string) (span : Token.span) : string list =
  let lines = String.split_on_char '\n' source in
  match List.nth_opt lines (span.Token.lo.Token.line - 1) with
  | None -> []
  | Some line ->
      let col = max 1 span.Token.lo.Token.col in
      let prefix =
        String.init (col - 1) (fun i ->
            if i < String.length line && line.[i] = '\t' then '\t' else ' ')
      in
      [ line; prefix ^ "^" ]

let print (sink : sink) : unit =
  List.iter
    (fun diagnostic ->
      prerr_endline (to_string diagnostic);
      match sink.source with
      | None -> ()
      | Some source ->
          List.iter prerr_endline (snippet source diagnostic.span))
    (all sink)
