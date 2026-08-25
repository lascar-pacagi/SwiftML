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

(* swiftc-style `file:line:col: severity: message`. We omit the filename here and
   let the driver prefix it. *)
let to_string (d : t) : string =
  Printf.sprintf "%d:%d: %s: %s" d.span.Token.lo.Token.line d.span.Token.lo.Token.col
    (string_of_severity d.severity) d.message

let print (s : sink) : unit =
  List.iter (fun d -> prerr_endline (to_string d)) (all s)
