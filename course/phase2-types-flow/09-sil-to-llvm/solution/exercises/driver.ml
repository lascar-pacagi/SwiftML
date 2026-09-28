(* The driver — a *contract* (given). The full Phase-2 pipeline:
   lex -> parse -> sema -> SILGen -> SIL -> IRGen -> LLVM IR -> clang -> native.
   Concept 09 adds `--emit-llvm` and `build` (programs finally run).

   WITH §6 EXERCISES APPLIED: 1 reports definite-initialization errors; 2 and 3 carry the
   C runtime (`runtime_c`) and link it into every build. *)

type emit =
  | Tokens
  | Ast
  | Typed_ast (* the TYPE-CHECKED tree sema produced *)
  | Check
  | Sil
  | Llvm (* + IRGen, print LLVM IR *)
  | Exe (* + clang: a native executable *)

let read_file (path : string) : string =
  let input_channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in input_channel)
    (fun () ->
      really_input_string input_channel (in_channel_length input_channel))

let frontend (source : string) (diagnostics : Diagnostics.sink) : Tast.program option =
  let tokens = Lexer.tokenize (Lexer.create source diagnostics) in
  let program = Parser.parse_program (Parser.create tokens diagnostics) in
  Sema.check program diagnostics

let bail_on_errors (diagnostics : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diagnostics then (
    Diagnostics.print diagnostics;
    exit 1)


(* EX3: the runtime, compiled from C and linked into every executable. IRGen calls these
   instead of emitting `printf` itself — the seed of a standard library. It travels as a string
   so a build needs no file of its own beside the compiler.

   EX2 lives in swiftml_print_double: Swift prints a Double with the SHORTEST digits that read
   back to the same value, plain between 1e-4 and 1e16 (with ".0" when whole) and in
   exponential form outside it — `0.1`, `1.0`, `0.30000000000000004`, `1e+16`, `1e-05`, all
   checked against swiftc. Shortest digits: try 1, 2, … 17 significant digits and keep the
   first that strtod turns back into the same bits. *)
let runtime_c = {|
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

void swiftml_print_int(long long v) { printf("%lld\n", v); }
void swiftml_print_bool(int b) { puts(b ? "true" : "false"); }
void swiftml_print_string(const char *s) { puts(s); }

void swiftml_print_double(double d) {
  if (isnan(d)) { puts("nan"); return; }
  if (isinf(d)) { puts(d < 0 ? "-inf" : "inf"); return; }
  char sci[40];
  for (int p = 1; p <= 17; p++) {
    snprintf(sci, sizeof sci, "%.*e", p - 1, d);
    if (strtod(sci, NULL) == d) break;
  }
  /* sci is [-]D[.DDD]e(+|-)XX: split it into sign, digits and decimal exponent */
  const char *q = sci; int neg = 0;
  if (*q == '-') { neg = 1; q++; }
  char dig[24]; int nd = 0;
  for (; *q && *q != 'e'; q++) if (*q != '.') dig[nd++] = *q;
  int e = atoi(q + 1);
  while (nd > 1 && dig[nd - 1] == '0') nd--;
  char out[400]; int k = 0;
  if (neg) out[k++] = '-';
  if (e < -4 || e >= 16) {                       /* exponential: 1e+16, 1.2345e-05 */
    out[k++] = dig[0];
    if (nd > 1) { out[k++] = '.'; for (int i = 1; i < nd; i++) out[k++] = dig[i]; }
    k += sprintf(out + k, "e%c%02d", e < 0 ? '-' : '+', e < 0 ? -e : e);
  } else if (e < 0) {                            /* 0.000123 */
    out[k++] = '0'; out[k++] = '.';
    for (int i = 0; i < -e - 1; i++) out[k++] = '0';
    for (int i = 0; i < nd; i++) out[k++] = dig[i];
  } else {                                       /* 123.45, and 100.0 for a whole number */
    for (int i = 0; i <= e; i++) out[k++] = i < nd ? dig[i] : '0';
    out[k++] = '.';
    if (nd > e + 1) for (int i = e + 1; i < nd; i++) out[k++] = dig[i];
    else out[k++] = '0';
  }
  out[k] = 0;
  puts(out);
}
|}

(* EX1: definite initialization ran inside SILGen; its errors are Swift diagnostics, reported
   like any other and at the read they are about *)
let report_di_errors (diagnostics : Diagnostics.sink) : unit =
  List.iter (fun (span, message) -> Diagnostics.error diagnostics span message)
    (List.rev !Silgen.di_errors);
  Silgen.di_errors := [];
  bail_on_errors diagnostics

(* source -> verified SIL -> LLVM IR text *)
let to_llvm ?(should_emit_terminator = fun _ -> true) (source : string)
    (diagnostics : Diagnostics.sink) : string =
  let program = frontend source diagnostics in
  bail_on_errors diagnostics;
  let sil_module = Silgen.lower (Option.get program) in
  report_di_errors diagnostics;
  (match Sil.verify sil_module with
  | [] -> ()
  | errors ->
      List.iter
        (fun message -> prerr_endline ("SIL verification error: " ^ message))
        errors;
      exit 1);
  Irgen.emit_llvm ~should_emit_terminator sil_module

let run_clang ~(ll_path : string) ~(out : string) : unit =
  (* EX3: the runtime is compiled alongside the module and linked into the executable *)
  let runtime_path = Filename.temp_file "swiftml_runtime" ".c" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove runtime_path with _ -> ())
    (fun () ->
      let channel = open_out runtime_path in
      output_string channel runtime_c;
      close_out channel;
      let command =
        Printf.sprintf "clang -Wno-override-module %s %s -o %s"
          (Filename.quote ll_path) (Filename.quote runtime_path) (Filename.quote out)
      in
      if Sys.command command <> 0 then
        failwith (Printf.sprintf "clang failed on %s" ll_path))

let compile_file ?(out = "a.out") ~(src_path : string) ~(emit : emit) () : unit
    =
  let source = read_file src_path in
  let diagnostics = Diagnostics.create ~source () in
  match emit with
  | Tokens ->
      let tokens = Lexer.tokenize (Lexer.create source diagnostics) in
      bail_on_errors diagnostics;
      List.iter
        (fun (token : Token.t) ->
          print_endline (Token.string_of_kind token.Token.kind))
        tokens
  | Ast ->
      let program =
        Parser.parse_program
          (Parser.create
             (Lexer.tokenize (Lexer.create source diagnostics))
             diagnostics)
      in
      bail_on_errors diagnostics;
      print_endline (Ast.dump_program program)
  | Check ->
      let (_ : Tast.program option) = frontend source diagnostics in
      bail_on_errors diagnostics
  | Typed_ast ->
        let typed = frontend source diagnostics in
        bail_on_errors diagnostics;
        Option.iter (fun p -> print_endline (Tast.dump_program p)) typed
  | Sil ->
      let program = frontend source diagnostics in
      bail_on_errors diagnostics;
      let sil_module = Silgen.lower (Option.get program) in
      report_di_errors diagnostics;
      print_endline (Sil.string_of_module sil_module)
  | Llvm -> print_string (to_llvm source diagnostics)
  | Exe ->
      let llvm_ir = to_llvm source diagnostics in
      let ll_path = Filename.temp_file "swiftml2" ".ll" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove ll_path with _ -> ())
        (fun () ->
          let output_channel = open_out ll_path in
          output_string output_channel llvm_ir;
          close_out output_channel;
          run_clang ~ll_path ~out)
