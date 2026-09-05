(* arm64.ml — a *contract*: the ARM64 (AArch64, Apple/macOS flavour) instruction IR + the asm
   printer. Concept 33's instruction selection (`isel.ml`) lowers SIL into a list of these per
   function; the printer renders them as `as`-assemblable text. (Concept 34 will reuse this IR and
   add VIRTUAL registers + register allocation; v0 uses physical registers + a stack-machine frame.)

   We target arm64-apple-macosx. Conventions that show up below:
   - integer registers x0..x30 (64-bit); w0..w30 are their 32-bit views. x0..x7 pass arguments and
     return values; x9..x15 are caller-saved scratch; x29 = frame pointer, x30 = link register, sp.
   - symbols are prefixed with `_` (so `main` -> `_main`, `printf` -> `_printf`).
   - PC-relative data addressing is a 2-step `adrp`/`add …@PAGE/@PAGEOFF` pair. *)

(* a register. v0 (concept 33) only uses physical regs; `Virt` is reserved for concept 34's
   register allocator (the printer rejects a leftover virtual register). *)
type reg =
  | X of int (* x0..x30, a 64-bit integer register *)
  | SP (* the stack pointer *)
  | XZR (* the zero register (reads as 0) *)
  | Virt of int (* a virtual register — concept 34; must be gone before printing *)

(* a condition code, for `b.<cond>` and `cset` *)
type cond = EQ | NE | LT | LE | GT | GE

(* an operand: a register or a (decimal) immediate *)
type operand = R of reg | Imm of int

type instr =
  | Mov of reg * operand (* mov rd, #imm | mov rd, rs *)
  | Movz of reg * int * int (* movz rd, #imm, lsl #shift — build a 64-bit constant *)
  | Movk of reg * int * int (* movk rd, #imm, lsl #shift *)
  | Add of reg * reg * operand
  | Sub of reg * reg * operand
  | Mul of reg * reg * reg
  | Sdiv of reg * reg * reg
  | Msub of reg * reg * reg * reg (* rd = ra - rn*rm  (used for `srem`) *)
  | Neg of reg * reg
  | And of reg * reg * operand
  | Orr of reg * reg * operand
  | Cmp of reg * operand
  | Cset of reg * cond (* rd = (cond) ? 1 : 0 *)
  | Csel of reg * reg * reg * cond (* rd = (cond) ? rt : rf *)
  | Ldr of reg * reg * int (* ldr rd, [rbase, #off] *)
  | Str of reg * reg * int (* str rs, [rbase, #off] *)
  | Stp of reg * reg * reg * int (* stp r1, r2, [rbase, #off] *)
  | Ldp of reg * reg * reg * int (* ldp r1, r2, [rbase, #off] *)
  | Adrp of reg * string (* adrp rd, sym@PAGE *)
  | AddSym of reg * reg * string (* add rd, rn, sym@PAGEOFF *)
  | B of string (* b label *)
  | Bcond of cond * string (* b.<cond> label *)
  | Bl of string (* bl _sym — a call *)
  | Brk of int (* brk #imm — a trap (SIGTRAP) *)
  | Ret
  | Label of string (* a branch target within a function *)
  | Comment of string (* a `; …` line, for readability *)
  | Loc of int (* a `.loc 1 N 0` source-line directive — debug info (concept 37) *)

(* a function. `instrs` may contain VIRTUAL registers before register allocation. The frame layout
   is a CONTRACT between isel (which picks the [sp, …] offsets) and regalloc (which must give a
   spilled virtual register the same home isel gave it): `outgoing` is the size in WORDS of the
   outgoing stack-argument area at the bottom of the frame (concept 35 — at least 2, for printf's
   variadic argument), and `nslots` is the total word count, that area plus one slot per value. So
   value v lives at [sp, #8*(outgoing + v)]. *)
type func = { name : string; instrs : instr list; nslots : int; outgoing : int }
type modul = {
  funcs : func list;
  cstrings : (string * string) list; (* (label, bytes) *)
  source : string; (* the source file path — for the `.file` directive (concept 37) *)
}

(* the register OPERANDS an instruction reads and writes — used by liveness and the vreg-rewrite in
   register allocation (concept 34). Memory base registers (sp) count as reads. *)
let reads_writes (i : instr) : reg list * reg list =
  match i with
  | Mov (d, R s) -> ([ s ], [ d ])
  | Mov (d, Imm _) | Movz (d, _, _) -> ([], [ d ])
  | Movk (d, _, _) -> ([ d ], [ d ]) (* movk merges into d, so it reads it too *)
  | Add (d, a, R b) | Sub (d, a, R b) | And (d, a, R b) | Orr (d, a, R b) -> ([ a; b ], [ d ])
  | Add (d, a, Imm _) | Sub (d, a, Imm _) | And (d, a, Imm _) | Orr (d, a, Imm _) -> ([ a ], [ d ])
  | Mul (d, a, b) | Sdiv (d, a, b) -> ([ a; b ], [ d ])
  | Msub (d, n, m, a) -> ([ n; m; a ], [ d ])
  | Neg (d, a) -> ([ a ], [ d ])
  | Cmp (a, R b) -> ([ a; b ], [])
  | Cmp (a, Imm _) -> ([ a ], [])
  | Cset (d, _) -> ([], [ d ])
  | Csel (d, t, f, _) -> ([ t; f ], [ d ])
  | Ldr (d, b, _) -> ([ b ], [ d ])
  | Str (s, b, _) -> ([ s; b ], [])
  | Stp (a, b, base, _) -> ([ a; b; base ], [])
  | Ldp (a, b, base, _) -> ([ base ], [ a; b ])
  | Adrp (d, _) -> ([], [ d ])
  | AddSym (d, a, _) -> ([ a ], [ d ])
  | B _ | Bcond _ | Bl _ | Brk _ | Ret | Label _ | Comment _ | Loc _ -> ([], [])

let is_virt = function Virt _ -> true | _ -> false

(* --- the asm printer --- *)

let reg_name = function
  | X 29 -> "x29"
  | X 30 -> "x30"
  | X n -> Printf.sprintf "x%d" n
  | SP -> "sp"
  | XZR -> "xzr"
  | Virt n -> failwith (Printf.sprintf "arm64: virtual register %%v%d reached the printer (run register allocation first)" n)

let op_str = function R r -> reg_name r | Imm n -> Printf.sprintf "#%d" n

let cond_suffix = function
  | EQ -> "eq" | NE -> "ne" | LT -> "lt" | LE -> "le" | GT -> "gt" | GE -> "ge"

let string_of_instr (i : instr) : string =
  let r = reg_name in
  match i with
  | Mov (d, o) -> Printf.sprintf "\tmov\t%s, %s" (r d) (op_str o)
  | Movz (d, imm, sh) -> Printf.sprintf "\tmovz\t%s, #%d, lsl #%d" (r d) imm sh
  | Movk (d, imm, sh) -> Printf.sprintf "\tmovk\t%s, #%d, lsl #%d" (r d) imm sh
  | Add (d, a, o) -> Printf.sprintf "\tadd\t%s, %s, %s" (r d) (r a) (op_str o)
  | Sub (d, a, o) -> Printf.sprintf "\tsub\t%s, %s, %s" (r d) (r a) (op_str o)
  | Mul (d, a, b) -> Printf.sprintf "\tmul\t%s, %s, %s" (r d) (r a) (r b)
  | Sdiv (d, a, b) -> Printf.sprintf "\tsdiv\t%s, %s, %s" (r d) (r a) (r b)
  | Msub (d, n, m, a) -> Printf.sprintf "\tmsub\t%s, %s, %s, %s" (r d) (r n) (r m) (r a)
  | Neg (d, a) -> Printf.sprintf "\tneg\t%s, %s" (r d) (r a)
  | And (d, a, o) -> Printf.sprintf "\tand\t%s, %s, %s" (r d) (r a) (op_str o)
  | Orr (d, a, o) -> Printf.sprintf "\torr\t%s, %s, %s" (r d) (r a) (op_str o)
  | Cmp (a, o) -> Printf.sprintf "\tcmp\t%s, %s" (r a) (op_str o)
  | Cset (d, c) -> Printf.sprintf "\tcset\t%s, %s" (r d) (cond_suffix c)
  | Csel (d, t, f, c) -> Printf.sprintf "\tcsel\t%s, %s, %s, %s" (r d) (r t) (r f) (cond_suffix c)
  | Ldr (d, b, off) -> Printf.sprintf "\tldr\t%s, [%s, #%d]" (r d) (r b) off
  | Str (s, b, off) -> Printf.sprintf "\tstr\t%s, [%s, #%d]" (r s) (r b) off
  | Stp (a, b, base, off) -> Printf.sprintf "\tstp\t%s, %s, [%s, #%d]" (r a) (r b) (r base) off
  | Ldp (a, b, base, off) -> Printf.sprintf "\tldp\t%s, %s, [%s, #%d]" (r a) (r b) (r base) off
  | Adrp (d, sym) -> Printf.sprintf "\tadrp\t%s, %s@PAGE" (r d) sym
  | AddSym (d, a, sym) -> Printf.sprintf "\tadd\t%s, %s, %s@PAGEOFF" (r d) (r a) sym
  | B l -> Printf.sprintf "\tb\t%s" l
  | Bcond (c, l) -> Printf.sprintf "\tb.%s\t%s" (cond_suffix c) l
  | Bl sym -> Printf.sprintf "\tbl\t%s" sym
  | Brk n -> Printf.sprintf "\tbrk\t#%d" n
  | Ret -> "\tret"
  | Label l -> Printf.sprintf "%s:" l
  | Comment s -> Printf.sprintf "\t; %s" s
  | Loc n -> Printf.sprintf "\t.loc\t1 %d 0" n

(* one C-string constant in the __TEXT,__cstring section *)
let string_of_cstring (label, bytes) : string =
  let esc =
    String.concat ""
      (List.map
         (fun c ->
           if c = '"' || c = '\\' then Printf.sprintf "\\%c" c
           else if Char.code c < 32 || Char.code c > 126 then Printf.sprintf "\\%03o" (Char.code c)
           else String.make 1 c)
         (List.init (String.length bytes) (String.get bytes)))
  in
  Printf.sprintf "%s:\n\t.asciz\t\"%s\"" label esc

let string_of_module (m : modul) : string =
  let b = Buffer.create 1024 in
  (* debug info (concept 37): name source file #1; the assembler turns the `.loc` directives below
     into a real DWARF line table when built with `-g`, so `lldb` can step by source line *)
  if m.source <> "" then Buffer.add_string b (Printf.sprintf "\t.file\t1 %S\n" m.source);
  Buffer.add_string b "\t.text\n";
  List.iter
    (fun (f : func) ->
      Buffer.add_string b (Printf.sprintf "\t.globl\t_%s\n\t.p2align 2\n_%s:\n" f.name f.name);
      List.iter (fun i -> Buffer.add_string b (string_of_instr i ^ "\n")) f.instrs)
    m.funcs;
  if m.cstrings <> [] then (
    Buffer.add_string b "\t.section\t__TEXT,__cstring,cstring_literals\n";
    List.iter (fun cs -> Buffer.add_string b (string_of_cstring cs ^ "\n")) m.cstrings);
  Buffer.contents b
