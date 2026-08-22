(* The driver (given). Full pipeline: lex -> parse -> sema -> SILGen -> SIL -> [optimizer]
   -> IRGen -> LLVM -> clang -> native. `-O` = SIL passes + clang -O2 (concept 20). *)

type emit =
  | Tokens
  | Ast
  | Check
  | Sil (* raw SIL (no optimization) *)
  | Sil_opt (* optimized SIL (`--sil-opt`) *)
  | Llvm (* + IRGen, print LLVM IR (optimized if -O) *)
  | Exe (* + clang: a native executable (optimized if -O) *)

let read_file (path : string) : string =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () -> really_input_string ic (in_channel_length ic))

let frontend (src : string) (diags : Diagnostics.sink) : Ast.program =
  let toks = Lexer.tokenize (Lexer.create src diags) in
  let prog = Parser.parse_program (Parser.create toks diags) in
  (* concept 40: macros expand BEFORE the type checker — an AST -> AST rewrite, so sema and SILGen
     only ever see ordinary, already-expanded code *)
  let prog = Macros.expand_program prog in
  Sema.check prog diags;
  prog

let bail_on_errors (diags : Diagnostics.sink) : unit =
  if Diagnostics.has_errors diags then (
    Diagnostics.print diags;
    exit 1)

(* source -> verified SIL (optimized if [opt]) *)
let lower_sil ?(opt = false) (src : string) (diags : Diagnostics.sink) : Sil.modul =
  let prog = frontend src diags in
  bail_on_errors diags;
  let m = Silgen.lower prog in
  (match Sil.verify m with
  | [] -> ()
  | errs ->
      List.iter (fun e -> prerr_endline ("SIL verification error: " ^ e)) errs;
      exit 1);
  (* concept 27: the OWNERSHIP verifier — ARC discipline checked statically, every compile *)
  (match Sil.verify_ownership m with
  | [] -> ()
  | errs ->
      List.iter (fun e -> prerr_endline ("ownership error: " ^ e)) errs;
      exit 1);
  if opt then Opt.optimize m else m

(* concept 38: the cooperative-coroutine runtime, in C, linked alongside the generated IR. async/
   await/Task lower to calls into this (rt_async_spawn / rt_async_yield / rt_async_run); the runtime
   gives each task its own stack (a STACKFUL coroutine via ucontext) and a FIFO ready queue. swiftc
   uses stackLESS coroutines (CPS state machines) for efficiency; we use stackful for simplicity —
   same observable semantics on a serial cooperative executor. The closure ABI ({code, ctx}) is
   passed by value (two registers), matching `swiftml_closure`. *)
let async_runtime_c =
  {c|
#define _XOPEN_SOURCE 700
#include <ucontext.h>
#include <stdlib.h>
typedef struct { void* code; void* ctx; } swiftml_closure;
typedef struct AsyncTask {
  ucontext_t uctx; swiftml_closure clo; int done; char* stack; struct AsyncTask* next;
} AsyncTask;
static AsyncTask* ready_head = 0;
static AsyncTask** ready_tail = &ready_head;
static ucontext_t sched_ctx;
static AsyncTask* current = 0;
static void enqueue(AsyncTask* t) { t->next = 0; *ready_tail = t; ready_tail = &t->next; }
static void task_trampoline(void) {
  ((void(*)(void*))current->clo.code)(current->clo.ctx);  /* run the task body to completion */
  current->done = 1;                                       /* uc_link returns us to the scheduler */
}
void rt_async_spawn(swiftml_closure c) {
  AsyncTask* t = (AsyncTask*)calloc(1, sizeof(AsyncTask));
  t->clo = c; t->stack = (char*)malloc(256*1024);
  getcontext(&t->uctx);
  t->uctx.uc_stack.ss_sp = t->stack; t->uctx.uc_stack.ss_size = 256*1024; t->uctx.uc_link = &sched_ctx;
  makecontext(&t->uctx, task_trampoline, 0);
  enqueue(t);
}
void rt_async_yield(void) {
  if (current) swapcontext(&current->uctx, &sched_ctx);   /* suspend; the scheduler runs the next */
}
void rt_async_run(void) {
  while (ready_head) {
    AsyncTask* t = ready_head; ready_head = t->next; if (!ready_head) ready_tail = &ready_head;
    current = t; swapcontext(&sched_ctx, &t->uctx); current = 0;  /* resume until it yields/finishes */
    if (t->done) { free(t->stack); free(t); } else enqueue(t);    /* yielded: re-enqueue (round robin) */
  }
}
|c}

let run_clang ~(opt : bool) ~(ll_path : string) ~(out : string) : unit =
  (* concept 20: `-O` also engages LLVM's optimizer — clang runs the full -O2 pass pipeline
     (instcombine, GVN, LICM, SCEV/indvars, vectorizer, …) and an optimizing backend (isel,
     register allocation, scheduling) on the IR we emit. `-Onone` compiles at -O0: fast, naive.
     concept 38: we also compile + link the C coroutine runtime (always; it has no `main`). *)
  let oflag = if opt then "-O2" else "-O0" in
  let rt_path = Filename.temp_file "swiftml_async_rt" ".c" in
  let oc = open_out rt_path in
  output_string oc async_runtime_c;
  close_out oc;
  let cmd =
    Printf.sprintf "clang %s -Wno-override-module -Wno-deprecated-declarations %s %s -o %s" oflag
      (Filename.quote ll_path) (Filename.quote rt_path) (Filename.quote out)
  in
  let rc = Sys.command cmd in
  (try Sys.remove rt_path with _ -> ());
  if rc <> 0 then failwith (Printf.sprintf "clang failed on %s" ll_path)

let compile_file ?(out = "a.out") ?(opt = false) ~(src_path : string) ~(emit : emit) () : unit =
  let src = read_file src_path in
  let diags = Diagnostics.create () in
  match emit with
  | Tokens ->
      let toks = Lexer.tokenize (Lexer.create src diags) in
      bail_on_errors diags;
      List.iter (fun (t : Token.t) -> print_endline (Token.string_of_kind t.Token.kind)) toks
  | Ast ->
      let prog = Parser.parse_program (Parser.create (Lexer.tokenize (Lexer.create src diags)) diags) in
      bail_on_errors diags;
      print_endline (Ast.dump_program prog)
  | Check ->
      let (_ : Ast.program) = frontend src diags in
      (* print warnings too (concept 23's always-fails cast warns like swiftc); errors exit 1 *)
      Diagnostics.print diags;
      if Diagnostics.has_errors diags then exit 1
  | Sil -> print_endline (Sil.string_of_module (lower_sil ~opt:false src diags))
  | Sil_opt -> print_endline (Sil.string_of_module (lower_sil ~opt:true src diags))
  | Llvm -> print_string (Irgen.emit_llvm (lower_sil ~opt src diags))
  | Exe ->
      let ll = Irgen.emit_llvm (lower_sil ~opt src diags) in
      let ll_path = Filename.temp_file "swiftml4" ".ll" in
      Fun.protect
        ~finally:(fun () -> try Sys.remove ll_path with _ -> ())
        (fun () ->
          let oc = open_out ll_path in
          output_string oc ll;
          close_out oc;
          run_clang ~opt ~ll_path ~out)
