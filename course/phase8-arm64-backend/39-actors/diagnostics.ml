(* Diagnostics — a *contract*, carried unchanged from Phase 1. Producers
   (lexer/parser/sema) call [error]/[warning]; the driver calls [print]/[has_errors].

   Design oracle: swift/include/swift/Basic/Diagnostic*.h *)

type severity =
  | Error
  | Warning
  | Note

type t = { severity : severity; span : Token.span; message : string }
type sink = { mutable diags : t list }

let create () : sink = { diags = [] }
let emit (s : sink) (d : t) = s.diags <- d :: s.diags
let error (s : sink) (span : Token.span) (message : string) = emit s { severity = Error; span; message }

let warning (s : sink) (span : Token.span) (message : string) =
  emit s { severity = Warning; span; message }

(* A note is not a problem in its own right: it explains the diagnostic above it, or points
   at the code that caused it (swiftc: `note: change 'let' to 'var' to make it mutable`).
   It never makes [has_errors] true. *)
let note (s : sink) (span : Token.span) (message : string) =
  emit s { severity = Note; span; message }

let has_errors (s : sink) = List.exists (fun d -> d.severity = Error) s.diags
let all (s : sink) : t list = List.rev s.diags
let string_of_severity = function Error -> "error" | Warning -> "warning" | Note -> "note"

let to_string (d : t) : string =
  Printf.sprintf "%d:%d: %s: %s" d.span.Token.lo.Token.line d.span.Token.lo.Token.col
    (string_of_severity d.severity) d.message

let print (s : sink) : unit = List.iter (fun d -> prerr_endline (to_string d)) (all s)
