(* AST for concept 10 — a *contract*. It carries every node the concepts before it
   introduced; the ones this concept adds, if any, are marked NEW below.

   WITH §6 EXERCISES APPLIED: EX1 adds methods and `mutating` to a struct body and the
   `recv.m(args)` call; EX2 adds computed properties; EX3 adds the conformance list
   (`struct Pair: Equatable`).

   Design oracle: swift/include/swift/AST/Decl.h (FuncDecl, ParamDecl), Stmt.h (ReturnStmt). *)

type binop =
  | Add
  | Sub
  | Mul
  | Div
  | Mod
  | Eq
  | Ne
  | Lt
  | Le
  | Gt
  | Ge
  | And
  | Or

type unop = Neg

type expr =
  | Int_lit of int * Token.span
  | Double_lit of float * Token.span
  | Bool_lit of bool * Token.span
  | String_lit of string * Token.span
  | Var of string * Token.span
  | Unary of unop * expr * Token.span
  | Binary of binop * expr * expr * Token.span
  | Call of string * arg list * Token.span (* function call OR struct init *)
  | Member of expr * string * Token.span (* NEW in this concept: `e.field` *)
  | Method_call of expr * string * arg list * Token.span (* EX1: `recv.m(args)` *)
  | Ascribe of expr * string * Token.span (* `e as T` — a coercion *)

(* a call/init argument may carry an external label, e.g. `Point(x: 1)` — concept 10 *)
and arg = string option * expr

type stmt =
  | Let of {
      name : string;
      is_var : bool;
      annot : string option;
      value : expr;
      span : Token.span;
    }
  | Assign of { name : string; value : expr; span : Token.span }
  | Set_member of {
      obj : string;
      field : string;
      value : expr;
      span : Token.span;
    }
    (* NEW in this concept: `p.x = e` *)
  | Expr_stmt of expr * Token.span
  | If of {
      cond : expr;
      then_blk : stmt list;
      else_blk : stmt list option;
      span : Token.span;
    }
  | While of { cond : expr; body : stmt list; span : Token.span }
  | For of {
      var : string;
      lo : expr;
      hi : expr;
      body : stmt list;
      span : Token.span;
    }
  | Break of Token.span
  | Continue of Token.span
  | Return of expr option * Token.span

(* functions *)
type param = {
  pname : string;
  ptype : string; (* written type name; sema resolves it *)
}

type func_decl = {
  fname : string;
  params : param list;
  ret : string option; (* the written return type name; None = Void *)
  body : stmt list;
  fspan : Token.span;
}

(* NEW in this concept: a struct declaration — stored properties in order *)
type field = {
  fld_name : string;
  fld_ty : string; (* written type name; sema resolves it *)
  fld_var : bool;
      (* `var x: T` — a `let` field can't be assigned through any binding *)
}

(* EX1: a method is a function declared in a struct body; `mutating` lets it change `self` *)
type method_decl = { mfunc : func_decl; mutating : bool }

(* EX2: `var area: Int { return … }` — a getter, with no storage in the layout *)
type computed = { cname : string; cty : string; cbody : stmt list; cspan : Token.span }

type struct_decl = {
  sname : string;
  sfields : field list;
  smethods : method_decl list; (* EX1 *)
  scomputed : computed list; (* EX2 *)
  sconforms : string list; (* EX3: the protocols after the name, `: Equatable` *)
  sspan : Token.span;
}
type item = IFunc of func_decl | IStruct of struct_decl | IStmt of stmt
type program = { items : item list }

let expr_span = function
  | Int_lit (_, span)
  | Double_lit (_, span)
  | Bool_lit (_, span)
  | String_lit (_, span)
  | Var (_, span)
  | Unary (_, _, span)
  | Binary (_, _, _, span)
  | Call (_, _, span)
  | Ascribe (_, _, span)
  | Member (_, _, span)
  | Method_call (_, _, _, span) ->
      span

let string_of_binop = function
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | Mod -> "%"
  | Eq -> "=="
  | Ne -> "!="
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | And -> "&&"
  | Or -> "||"

let string_of_unop = function Neg -> "-"

let rec dump_expr = function
  | Int_lit (integer, _) -> string_of_int integer
  | Double_lit (number, _) -> Printf.sprintf "%g" number
  | Bool_lit (boolean, _) -> string_of_bool boolean
  | String_lit (text, _) -> Printf.sprintf "%S" text
  | Var (name, _) -> name
  | Unary (operator, expression, _) ->
      Printf.sprintf "(%s %s)" (string_of_unop operator) (dump_expr expression)
  | Binary (operator, left, right, _) ->
      Printf.sprintf "(%s %s %s)" (string_of_binop operator) (dump_expr left)
        (dump_expr right)
  | Ascribe (expression, type_name, _) ->
      Printf.sprintf "(as %s %s)" type_name (dump_expr expression)
  | Call (function_name, arguments, _) ->
      let dump_argument (label, expression) =
        match label with
        | Some label -> Printf.sprintf "%s:%s" label (dump_expr expression)
        | None -> dump_expr expression
      in
      Printf.sprintf "(%s %s)" function_name
        (String.concat " " (List.map dump_argument arguments))
  | Member (expression, field_name, _) ->
      Printf.sprintf "(. %s %s)" (dump_expr expression) field_name
  | Method_call (receiver, method_name, arguments, _) ->
      let dump_argument (label, expression) =
        match label with
        | Some label -> Printf.sprintf "%s:%s" label (dump_expr expression)
        | None -> dump_expr expression
      in
      Printf.sprintf "(.call %s %s%s)" (dump_expr receiver) method_name
        (String.concat "" (List.map (fun a -> " " ^ dump_argument a) arguments))

let rec dump_stmt = function
  | Let { name; is_var; annot; value; _ } -> (
      let keyword = if is_var then "var" else "let" in
      match annot with
      | None -> Printf.sprintf "(%s %s %s)" keyword name (dump_expr value)
      | Some type_name ->
          Printf.sprintf "(%s %s : %s %s)" keyword name type_name
            (dump_expr value))
  | Assign { name; value; _ } ->
      Printf.sprintf "(= %s %s)" name (dump_expr value)
  | Set_member { obj; field; value; _ } ->
      Printf.sprintf "(.= %s %s %s)" obj field (dump_expr value)
  | Expr_stmt (expression, _) -> dump_expr expression
  | If { cond; then_blk; else_blk; _ } -> (
      match else_blk with
      | None ->
          Printf.sprintf "(if %s %s)" (dump_expr cond) (dump_block then_blk)
      | Some statements ->
          Printf.sprintf "(if %s %s %s)" (dump_expr cond) (dump_block then_blk)
            (dump_block statements))
  | While { cond; body; _ } ->
      Printf.sprintf "(while %s %s)" (dump_expr cond) (dump_block body)
  | For { var; lo; hi; body; _ } ->
      Printf.sprintf "(for %s %s %s %s)" var (dump_expr lo) (dump_expr hi)
        (dump_block body)
  | Break _ -> "break"
  | Continue _ -> "continue"
  | Return (None, _) -> "(return)"
  | Return (Some expression, _) ->
      Printf.sprintf "(return %s)" (dump_expr expression)

and dump_block (statements : stmt list) : string =
  Printf.sprintf "(%s)" (String.concat " " (List.map dump_stmt statements))

let dump_param (parameter : param) : string =
  Printf.sprintf "%s:%s" parameter.pname parameter.ptype

let dump_func (function_decl : func_decl) : string =
  let parameters =
    String.concat " " (List.map dump_param function_decl.params)
  in
  let return_type =
    match function_decl.ret with
    | Some type_name -> Printf.sprintf "-> %s " type_name
    | None -> ""
  in
  Printf.sprintf "(func %s (%s) %s%s)" function_decl.fname parameters
    return_type
    (dump_block function_decl.body)

let dump_field (field : field) : string =
  Printf.sprintf "%s%s:%s"
    (if field.fld_var then "" else "let ")
    field.fld_name field.fld_ty

(* the extra parts print only when present, so a plain struct dumps exactly as before *)
let dump_struct (struct_decl : struct_decl) : string =
  let conforms =
    match struct_decl.sconforms with
    | [] -> ""
    | protocols -> ": " ^ String.concat ", " protocols ^ " "
  in
  let methods =
    List.map
      (fun m -> (if m.mutating then " mutating " else " ") ^ dump_func m.mfunc)
      struct_decl.smethods
  in
  let computed =
    List.map
      (fun c -> Printf.sprintf " (get %s:%s %s)" c.cname c.cty (dump_block c.cbody))
      struct_decl.scomputed
  in
  Printf.sprintf "(struct %s %s(%s)%s)" struct_decl.sname conforms
    (String.concat " " (List.map dump_field struct_decl.sfields))
    (String.concat "" (methods @ computed))

let dump_item = function
  | IFunc function_decl -> dump_func function_decl
  | IStruct struct_decl -> dump_struct struct_decl
  | IStmt statement -> dump_stmt statement

let dump_program (program : program) : string =
  String.concat "\n" (List.map dump_item program.items)
