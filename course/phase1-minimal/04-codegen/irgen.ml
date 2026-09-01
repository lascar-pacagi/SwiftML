(* The IR generator: lower the checked AST straight to LLVM IR *text*.

   Phase-1 IRGen lowers to LLVM IR text (no SIL yet; that arrives in Phase 2). A simple
   stack/value model: every binding gets an `alloca`, reads are `load`, writes are
   `store`. Phase 4's mem2reg promotes these to SSA.

   >>> You build this in concept  phase1-minimal/04-codegen. <<<

   Four holes, each one testable on its own — see explainer §3 for the order and
   `tests/test_irgen.ml` for the group each one turns green.

   Design oracle: swift/lib/IRGen/* ; LLVM LangRef. We emit opaque-pointer IR (`ptr`),
   which Apple clang (LLVM 15+) consumes directly, and print via libc `printf`. *)

(* GIVEN — the state the lowering shares, and its two helpers. swiftc bundles the same
   three things in `IRGenFunction` (IRGenFunction.h:77): somewhere to put instructions,
   a way to name values, and the map from source names to their storage. *)
type ctx = {
  buf : Buffer.t; (* the instructions of `main`, in order *)
  mutable next_reg : int; (* how many %tN names have been handed out *)
  slots : (string, string) Hashtbl.t; (* source name -> the alloca register holding it *)
  name_to_value : (string, string) Hashtbl.t;
}

let create () : ctx = { 
   buf = Buffer.create 256; 
   next_reg = 0; 
   slots = Hashtbl.create 16;
   name_to_value = Hashtbl.create 16;
}

(* append one instruction, indented like the body of a function *)
let emit (c : ctx) (line : string) : unit = Buffer.add_string c.buf ("  " ^ line ^ "\n")

(* a register name nobody has used yet: %t1, %t2, … ("%%" is a literal '%') *)
let fresh (c : ctx) : string =
  c.next_reg <- c.next_reg + 1;
  Printf.sprintf "%%t%d" c.next_reg

(* The slot a name lives in — the register `alloca` returned. First use emits the
   `alloca`; later uses must find the SAME register, so a reassigned `var` stores into
   its existing slot instead of allocating a second one.   Tests: `slots`. *)
let slot_of (c : ctx) (name : string) : string =
   match Hashtbl.find_opt c.slots name with
   | Some t -> t
   | None -> begin
      let t = fresh c in
      Printf.sprintf "%s = alloca i64" t
      |> emit c;
      Hashtbl.add c.slots name t;
      t
   end
   (* ignore (c, name);
   failwith "TODO(04b): the name -> slot map (alloca on first use, remembered after)" *)


let rec constant_folding (c : ctx) (e : Ast.expr) : int option =
   match e with
   | Ast.Int_lit (i, _) -> Some i
   | Ast.Unary (Neg, e, _) -> begin 
      constant_folding c e 
      |> Option.map (fun x -> -x)
   end
   | Ast.Binary (op, e1, e2, _) -> begin
      Option.bind (constant_folding c e1) 
      (fun a ->         
         Option.bind (constant_folding c e2) 
         (fun b ->
            match op with
            | Add -> Some (a + b)
            | Sub -> Some (a - b) 
            | Mul -> Some (a * b)
            | Div -> if b = 0 then None else Some (a / b)
            | Mod -> if b = 0 then None else Some (a mod b)
         )
      )
   end
   | Ast.Var (x, _) ->
      Option.bind (Hashtbl.find_opt c.name_to_value x) int_of_string_opt
   | _ -> None 

(* Lower an expression: emit its instructions, RETURN the operand holding its result —
   an immediate like "42", or a register like "%t3". That returned string is the whole
   interface: a literal emits nothing and returns itself, a binary emits one instruction
   and returns its register. §2 has the opcode table.

   `print` is the one call we lower, and it is Void in Swift: nothing consumes its result.
   Return an immediate for it — what printf hands back is an i32 (the character count),
   ill-typed anywhere an i64 is expected.   Tests: `arithmetic`, `literals`. *)
let rec emit_expr (c : ctx) (e : Ast.expr) : string =
   match constant_folding c e with
   | Some i -> string_of_int i
   | None ->
      match e with
      | Ast.Int_lit (i, _) -> string_of_int i
      | Ast.Var (x, _) -> begin
         match Hashtbl.find_opt c.name_to_value x with
         | Some t -> t
         | None ->    
            let tx = slot_of c x in
            let t = fresh c in
            Printf.sprintf "%s = load i64, ptr %s" t tx
            |> emit c;
            t
      end
      | Ast.Unary (Neg, e', _) -> begin 
         let te = emit_expr c e' in
         let t = fresh c in
         Printf.sprintf "%s = sub i64 0, %s" t te
         |> emit c;
         t 
      end
      | Ast.Binary (op, e1, e2, _) -> begin
         let te1 = emit_expr c e1 in
         let te2 = emit_expr c e2 in
         let t = fresh c in
         Printf.sprintf "%s = %s i64 %s, %s" t (
            match op with
            | Add -> "add"
            | Sub -> "sub" 
            | Mul -> "mul"
            | Div -> "sdiv"
            | Mod -> "srem"
         ) te1 te2
         |> emit c;
         t
      end
      | Call ("print", [a], _) -> begin
         let ta = emit_expr c a in
         let t = fresh c in
         Printf.sprintf "%s = call i32 (ptr, ...) @printf(ptr @.fmt, i64 %s)" t ta
         |> emit c;
         "0"
      end 
      | _ -> assert false
  (* ignore (c, e, fresh, emit, slot_of, emit_expr);
  failwith "TODO(04a): lower an expression, returning its operand" *)


(* Lower a statement: `let`/`var` and assignment store into the name's slot; a bare
   expression is emitted for its instructions and its operand dropped.  Tests: `slots`. *)
let emit_stmt (c : ctx) (s : Ast.stmt) : unit =
   match s with
   | Let { name; is_var = _; value; span = _ } -> begin
      let tv = emit_expr c value in
      match Hashtbl.find_opt c.name_to_value name with
      | Some _ -> Hashtbl.add c.name_to_value name tv
      | None ->
         let t = slot_of c name in
         Printf.sprintf "store i64 %s, ptr %s" tv t
         |> emit c
   end
   | Assign { name; value; span = _ } -> begin
      let tv = emit_expr c value in
      let t = slot_of c name in 
      Printf.sprintf "store i64 %s, ptr %s" tv t
      |> emit c
   end
   | Expr_stmt (e, _) -> ignore (emit_expr c e)
   (* ignore (c, s, emit_expr);
  failwith "TODO(04c): lower a statement" *)

let find_const (c : ctx) (prog : Ast.program) : unit =
   List.iter (function 
   | Ast.Let { name; is_var = _; value = _; span = _ } ->
      Hashtbl.replace c.name_to_value name ""
   | Ast.Assign { name; value = _; span = _ } ->
      Hashtbl.remove c.name_to_value name
   | Ast.Expr_stmt _ -> ()) prog.stmts

(* The whole module: the `@.fmt` constant and `declare i32 @printf(ptr, ...)`, then
   `define i32 @main() {`, `entry:`, every statement in order, `ret i32 0`, `}`.
   The preamble is module-level, so it is not written with `emit` (which indents for a
   function body) — build the string around `Buffer.contents c.buf`.  Tests: `module`. *)
let emit_llvm (prog : Ast.program) : string =
   let c = create () in
   find_const c prog;
   let preamble = {|; swiftml Phase-1 LLVM IR
@.fmt = private unnamed_addr constant [6 x i8] c"%lld\0A\00"
declare i32 @printf(ptr, ...)

define i32 @main() {
entry:
|} in
   List.iter (emit_stmt c) prog.stmts;
   preamble ^ Buffer.contents c.buf ^ "  ret i32 0\n}\n"
   (* ignore (prog, create, emit_stmt);
   failwith "TODO(04d): assemble the module" *)


(* fold returns the rewritten expression AND, when that expression is a constant, its
     value. Children are folded once; the parent reads their values instead of walking
     them again, so the whole pass is linear in the size of the tree. *)
let eval_op (op : Ast.binop) (a : int) (b : int) : int option =
   match op with
   | Ast.Add -> Some (a + b)
   | Ast.Sub -> Some (a - b)
   | Ast.Mul -> Some (a * b)
   (* division and remainder by zero must reach the machine: the program traps there,
      and folding it here would raise Division_by_zero inside the compiler instead *)
   | Ast.Div -> if b = 0 then None else Some (a / b)
   | Ast.Mod -> if b = 0 then None else Some (a mod b)

let rec fold (e : Ast.expr) : Ast.expr * int option =
   match e with
   | Ast.Int_lit (n, _) -> (e, Some n)
   | Ast.Var _ -> (e, None)
   | Ast.Unary (Ast.Neg, x, sp) -> (
      let x', v = fold x in
      match v with
      | Some n -> (Ast.Int_lit (-n, sp), Some (-n))
      | None -> (Ast.Unary (Ast.Neg, x', sp), None))
   | Ast.Binary (op, l, r, sp) -> (
      let l', a = fold l in
      let r', b = fold r in
      match (a, b) with
      | Some a, Some b -> (
         match eval_op op a b with
         | Some n -> (Ast.Int_lit (n, sp), Some n)
         | None -> (Ast.Binary (op, l', r', sp), None))
      | _ -> (Ast.Binary (op, l', r', sp), None))
   | Ast.Call (f, args, sp) -> (Ast.Call (f, List.map (fun a -> fst (fold a)) args, sp), None)

(* statements are inline records, so each one is destructured and rebuilt *)
let fold_stmt (s : Ast.stmt) : Ast.stmt =
   match s with
   | Ast.Let { name; is_var; value; span } ->
      Ast.Let { name; is_var; value = fst (fold value); span }
   | Ast.Assign { name; value; span } -> Ast.Assign { name; value = fst (fold value); span }
   | Ast.Expr_stmt (e, sp) -> Ast.Expr_stmt (fst (fold e), sp)