(* Diagnostics: how the compiler reports errors/warnings to the user.

   Design oracle:
     swift/include/swift/Basic/Diagnostic*.h
     swift/lib/AST/DiagnosticEngine.cpp
   Swift has a rich engine (fix-its, categories, localization). Ours starts as a
   simple collected list; you grow it (source snippets, carets, fix-its) over time.

   This file is a *contract* (fully written). Producers (lexer/parser/sema) call
   [error]/[warning]; the driver calls [print] and checks [has_errors]. *)

type severity =
  | Error
  | Warning
  | Note

type t = { severity : severity; span : Token.span; message : string }

(* A mutable sink threaded through the front end. *)
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

(* swiftc-style `file:line:col: severity: message`. We omit the filename here and
   let the driver prefix it. *)
let to_string (diagnostic : t) : string =
  Printf.sprintf "%d:%d: %s: %s" diagnostic.span.Token.lo.Token.line
    diagnostic.span.Token.lo.Token.col (string_of_severity diagnostic.severity) diagnostic.message

let print (sink : sink) : unit =
  List.iter (fun diagnostic -> prerr_endline (to_string diagnostic)) (all sink)
