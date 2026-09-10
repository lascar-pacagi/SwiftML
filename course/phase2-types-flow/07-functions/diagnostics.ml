(* Diagnostics — a *contract*, carried unchanged from Phase 1. Producers
   (lexer/parser/sema) call [error]/[warning]; the driver calls [print]/[has_errors].

   Design oracle: swift/include/swift/Basic/Diagnostic*.h *)

type severity =
  | Error
  | Warning
  | Note

type t = { severity : severity; span : Token.span; message : string }
type sink = { mutable diagnostics : t list }

let create () : sink = { diagnostics = [] }
let emit (sink : sink) (diagnostic : t) =
  sink.diagnostics <- diagnostic :: sink.diagnostics
let error (sink : sink) (span : Token.span) (message : string) = emit sink { severity = Error; span; message }

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
let string_of_severity = function Error -> "error" | Warning -> "warning" | Note -> "note"

let to_string (diagnostic : t) : string =
  Printf.sprintf "%d:%d: %s: %s" diagnostic.span.Token.lo.Token.line
    diagnostic.span.Token.lo.Token.col (string_of_severity diagnostic.severity) diagnostic.message

let print (sink : sink) : unit =
  List.iter (fun diagnostic -> prerr_endline (to_string diagnostic)) (all sink)
