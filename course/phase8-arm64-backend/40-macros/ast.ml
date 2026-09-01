(* AST for concept 07 — a *contract*. Concept-06 nodes + functions: a parameter, a
   function declaration, a `return` statement, and a top-level *item* that is either a
   function or a statement (so a program is an interleaving of the two).

   Design oracle: swift/include/swift/AST/Decl.h (FuncDecl, ParamDecl), Stmt.h (ReturnStmt). *)

type binop =
  | Add | Sub | Mul | Div | Mod
  | Eq | Ne | Lt | Le | Gt | Ge
  | And | Or

type unop = Neg

(* `try` flavour — concept 30 *)
and try_kind = TryPlain | TryOptional | TryForce

(* a function/closure parameter (used by both `func` decls and closure literals) *)
type param = { pname : string; ptype : string (* written type name; sema resolves it *) }

type expr =
  | Int_lit of int * Token.span
  | Double_lit of float * Token.span
  | Bool_lit of bool * Token.span
  | String_lit of string * Token.span
  | Var of string * Token.span
  | Unary of unop * expr * Token.span
  | Binary of binop * expr * expr * Token.span
  | Call of string * (string option * expr) list * Token.span (* function call OR struct init *)
  | Member of expr * string * Token.span (* `e.field` (concept 10) / `E.case` / `e.rawValue` (11) *)
  | Method_call of expr * string * (string option * expr) list * Token.span (* `e.name(args)` — 11: `E.case(args)` *)
  (* optionals — concept 13 *)
  | Nil of Token.span (* the `nil` literal (contextually typed) *)
  | Force_unwrap of expr * Token.span (* `e!` — traps if nil *)
  | Coalesce of expr * expr * Token.span (* `a ?? b` *)
  | Ternary of expr * expr * expr * Token.span (* `c ? a : b` — the value-producing diamond *)
  (* NEW (concept 23): dynamic casts on existentials. `e as? T` (conditional -> T?) and
     `e as! T` (forced -> T, aborts on mismatch). *)
  | Cast of expr * string * bool (* conditional? *) * Token.span
  (* NEW (concept 29): a closure literal `{ (x: Int) -> Int in <expr> }` — explicitly typed
     parameters, a single-expression body (multi-statement bodies are an exercise). Free
     variables of the body are CAPTURED by value at creation. *)
  | Closure of param list * string option * expr * Token.span
  (* NEW (concept 30): `try e` / `try? e` / `try! e` — the call site of a throwing call. *)
  | Try of try_kind * expr * Token.span
  | Await of expr * Token.span (* concept 38: `await e` *)
  | MacroExpr of string * expr list * Token.span (* concept 40: `#name(args)` *)
  (* collections — concept 31 *)
  | Array_lit of expr list * Token.span       (* `[a, b, c]` (element type from context/first) *)
  | Subscript of expr * expr * Token.span      (* `a[i]` — read *)
  (* NEW (concept 05): `e as T` — a *coercion*. The type is written, so `infer` has
     nothing to synthesise and must CHECK the operand against it. *)
  | Ascribe of expr * string * Token.span

(* a call/init argument may carry an external label, e.g. `Point(x: 1)` — concept 10 *)
type arg = string option * expr

(* NEW (concept 12): patterns for `switch`. A binding is `let x` (Bind) or `_` (Ignore). *)
type pat_binding = Bind of string | Ignore
type pattern =
  | PEnumCase of string * pat_binding list (* `.circle(let r)` / `.dot` *)
  | PInt of int (* a literal Int pattern: `0`, `-1` *)

type stmt =
  | Let of { name : string; is_var : bool; annot : string option; value : expr; span : Token.span }
  | Assign of { name : string; value : expr; span : Token.span }
  | Set_member of { obj : string; field : string; value : expr; span : Token.span } (* NEW: `p.x = e` *)
  | Expr_stmt of expr * Token.span
  | If of { cond : expr; then_blk : stmt list; else_blk : stmt list option; span : Token.span }
  (* NEW (concept 13): `if let name = opt { … } [else { … }]` — optional binding *)
  | If_let of { name : string; opt : expr; then_blk : stmt list; else_blk : stmt list option; span : Token.span }
  | While of { cond : expr; body : stmt list; span : Token.span }
  | For of { var : string; lo : expr; hi : expr; body : stmt list; span : Token.span }
  (* NEW (concept 12): `switch subject { case <pat>: <body> … [default: <body>] }` *)
  | Switch of {
      subject : expr;
      cases : (pattern * stmt list) list;
      default : stmt list option;
      span : Token.span;
    }
  | Break of Token.span
  | Continue of Token.span
  | Return of expr option * Token.span
  (* error handling — concept 30 *)
  | Throw of expr * Token.span
  | Spawn of stmt list * Token.span (* concept 38: `Task { … }` *)
  (* collections — concept 31 *)
  | Set_subscript of { arr : string; index : expr; value : expr; span : Token.span } (* `a[i] = e` *)
  | For_in of { var : string; seq : expr; body : stmt list; span : Token.span }       (* `for x in arr` *)
  | Do of { body : stmt list; catches : catch_clause list; span : Token.span }
  | Defer of stmt list * Token.span

(* a `catch` clause: an optional enum-case pattern (`catch E.case`), else a bare `catch` (any).
   `cbind` is the `catch let e`-style binding (None in v0; reserved). *)
and catch_clause = { cpat : (string * string) option; cbind : string option; cbody : stmt list }

(* (param moved above `expr` — closures reference it; concept 29) *)

type func_decl = {
  fname : string;
  generics : (string * string option) list;
    (* NEW (concept 22): type parameters with their constraint — `<T: P>` = [("T", Some "P")].
       A `where T: P` clause fills the constraint the same way. v0 requires a constraint. *)
  params : param list;
  throws : bool; (* NEW (concept 30): declared `throws` *)
  is_async : bool; (* NEW (concept 38): declared `async` *)
  ret : string option; (* the written return type name; None = Void *)
  body : stmt list;
  fspan : Token.span;
}

(* a struct declaration (concept 10) — stored properties in order. Concept 21 adds
   `sconforms` (the `: P, Q` conformance clause) and `smethods` (non-mutating methods —
   each is a func_decl whose body may use `self` and bare field/method names). *)
type field = { fld_name : string; fld_ty : string (* written type name; sema resolves it *) }
type struct_decl = {
  sname : string;
  sconforms : string list; (* NEW (21): protocols this struct declares conformance to *)
  sfields : field list;
  smethods : func_decl list; (* NEW (21): methods, lowered as `S.name` with self as arg 0 *)
  sspan : Token.span;
}

(* NEW (concept 25): a class declaration — stored properties, ONE initializer (v0), methods
   (each flagged if it `override`s), an optional superclass. *)
type class_decl = {
  cname : string;
  csuper : string option;
  cfields : field list;
  cinit : func_decl option; (* fname = "init"; ret ignored *)
  cdeinit : stmt list option; (* NEW (concept 26): the `deinit { … }` body *)
  cmethods : (bool * func_decl) list; (* (is_override, decl) *)
  is_actor : bool; (* NEW (concept 39): `actor` vs `class` *)
  cspan : Token.span;
}

(* NEW (concept 21): a protocol declaration — METHOD REQUIREMENTS only (signatures, no
   bodies). Property/init/associated-type requirements are later concepts/exercises. *)
type proto_req = { rname : string; rparams : param list; rret : string option }
type proto_decl = { pname : string; reqs : proto_req list; pspan : Token.span }

(* NEW (concept 11): an enum declaration — cases in order; each case has payload type names
   (empty for a simple case). eraw = Some "Int" for a `: Int` raw-value enum. *)
type enum_case = { cname : string; payload : string list }
type enum_decl = {
  ename : string;
  ecases : enum_case list;
  eraw : string option;
  is_error : bool; (* NEW (concept 30): declared `: Error` — an error type *)
  espan : Token.span;
}

type item =
  | IFunc of func_decl
  | IStruct of struct_decl
  | IEnum of enum_decl
  | IProto of proto_decl (* NEW (concept 21) *)
  | IClass of class_decl (* NEW (concept 25) *)
  | IStmt of stmt

type program = { items : item list }

let expr_span = function
  | Int_lit (_, s)
  | Double_lit (_, s)
  | Bool_lit (_, s)
  | String_lit (_, s)
  | Var (_, s)
  | Unary (_, _, s)
  | Binary (_, _, _, s)
  | Call (_, _, s)
  | Ascribe (_, _, s)
  | Member (_, _, s)
  | Method_call (_, _, _, s)
  | Nil s
  | Force_unwrap (_, s)
  | Coalesce (_, _, s)
  | Ternary (_, _, _, s)
  | Cast (_, _, _, s)
  | Closure (_, _, _, s)
  | Try (_, _, s)
  | Array_lit (_, s)
  | Subscript (_, _, s)
  | Await (_, s)
  | MacroExpr (_, _, s) ->
      s

let string_of_binop = function
  | Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/" | Mod -> "%"
  | Eq -> "==" | Ne -> "!=" | Lt -> "<" | Le -> "<=" | Gt -> ">" | Ge -> ">="
  | And -> "&&" | Or -> "||"

let string_of_unop = function Neg -> "-"

let rec dump_expr = function
  | Int_lit (n, _) -> string_of_int n
  | Double_lit (f, _) -> Printf.sprintf "%g" f
  | Bool_lit (b, _) -> string_of_bool b
  | String_lit (s, _) -> Printf.sprintf "%S" s
  | Var (x, _) -> x
  | Unary (op, e, _) -> Printf.sprintf "(%s %s)" (string_of_unop op) (dump_expr e)
  | Cast (e, t, c, _) -> Printf.sprintf "(as%s %s %s)" (if c then "?" else "!") (dump_expr e) t
  | Closure (ps, r, body, _) ->
      Printf.sprintf "(closure (%s)%s %s)"
        (String.concat " " (List.map (fun (p : param) -> p.pname ^ ":" ^ p.ptype) ps))
        (match r with Some t -> " -> " ^ t | None -> "")
        (dump_expr body)
  | Binary (op, l, r, _) ->
      Printf.sprintf "(%s %s %s)" (string_of_binop op) (dump_expr l) (dump_expr r)
  | Ascribe (e, t, _) -> Printf.sprintf "(as %s %s)" t (dump_expr e)
  | Call (f, args, _) ->
      Printf.sprintf "(%s %s)" f (String.concat " " (List.map dump_arg args))
  | Member (e, fld, _) -> Printf.sprintf "(. %s %s)" (dump_expr e) fld
  | Method_call (e, m, args, _) ->
      Printf.sprintf "(.call %s %s %s)" (dump_expr e) m (String.concat " " (List.map dump_arg args))
  | Nil _ -> "nil"
  | Force_unwrap (e, _) -> Printf.sprintf "(! %s)" (dump_expr e)
  | Await (e, _) -> Printf.sprintf "(await %s)" (dump_expr e)
  | MacroExpr (n, args, _) -> Printf.sprintf "(macro #%s %s)" n (String.concat " " (List.map dump_expr args))
  | Coalesce (a, b, _) -> Printf.sprintf "(?? %s %s)" (dump_expr a) (dump_expr b)
  | Ternary (c, a, b, _) -> Printf.sprintf "(?: %s %s %s)" (dump_expr c) (dump_expr a) (dump_expr b)
  | Try (k, e, _) ->
      let m = match k with TryPlain -> "try" | TryOptional -> "try?" | TryForce -> "try!" in
      Printf.sprintf "(%s %s)" m (dump_expr e)
  | Array_lit (es, _) -> Printf.sprintf "[%s]" (String.concat " " (List.map dump_expr es))
  | Subscript (a, i, _) -> Printf.sprintf "(sub %s %s)" (dump_expr a) (dump_expr i)

and dump_arg (l, e) =
  match l with Some lbl -> Printf.sprintf "%s:%s" lbl (dump_expr e) | None -> dump_expr e

let rec dump_stmt = function
  | Let { name; is_var; annot; value; _ } ->
      let kw = if is_var then "var" else "let" in
      (match annot with
      | None -> Printf.sprintf "(%s %s %s)" kw name (dump_expr value)
      | Some t -> Printf.sprintf "(%s %s : %s %s)" kw name t (dump_expr value))
  | Assign { name; value; _ } -> Printf.sprintf "(= %s %s)" name (dump_expr value)
  | Set_member { obj; field; value; _ } -> Printf.sprintf "(.= %s %s %s)" obj field (dump_expr value)
  | Expr_stmt (e, _) -> dump_expr e
  | If { cond; then_blk; else_blk; _ } -> (
      match else_blk with
      | None -> Printf.sprintf "(if %s %s)" (dump_expr cond) (dump_block then_blk)
      | Some e -> Printf.sprintf "(if %s %s %s)" (dump_expr cond) (dump_block then_blk) (dump_block e))
  | If_let { name; opt; then_blk; else_blk; _ } -> (
      match else_blk with
      | None -> Printf.sprintf "(iflet %s %s %s)" name (dump_expr opt) (dump_block then_blk)
      | Some e -> Printf.sprintf "(iflet %s %s %s %s)" name (dump_expr opt) (dump_block then_blk) (dump_block e))
  | While { cond; body; _ } -> Printf.sprintf "(while %s %s)" (dump_expr cond) (dump_block body)
  | For { var; lo; hi; body; _ } ->
      Printf.sprintf "(for %s %s %s %s)" var (dump_expr lo) (dump_expr hi) (dump_block body)
  | Switch { subject; cases; default; _ } ->
      let dump_bind = function Bind x -> "let " ^ x | Ignore -> "_" in
      let dump_pat = function
        | PEnumCase (c, []) -> "." ^ c
        | PEnumCase (c, bs) -> Printf.sprintf ".%s(%s)" c (String.concat "," (List.map dump_bind bs))
        | PInt n -> string_of_int n
      in
      let dcase (p, body) = Printf.sprintf "(case %s %s)" (dump_pat p) (dump_block body) in
      let dflt = match default with Some b -> " (default " ^ dump_block b ^ ")" | None -> "" in
      Printf.sprintf "(switch %s %s%s)" (dump_expr subject) (String.concat " " (List.map dcase cases)) dflt
  | Break _ -> "break"
  | Continue _ -> "continue"
  | Return (None, _) -> "(return)"
  | Return (Some e, _) -> Printf.sprintf "(return %s)" (dump_expr e)
  | Throw (e, _) -> Printf.sprintf "(throw %s)" (dump_expr e)
  | Spawn (body, _) -> Printf.sprintf "(spawn %s)" (String.concat " " (List.map dump_stmt body))
  | Set_subscript { arr; index; value; _ } -> Printf.sprintf "(sub= %s %s %s)" arr (dump_expr index) (dump_expr value)
  | For_in { var; seq; body; _ } -> Printf.sprintf "(forin %s %s %s)" var (dump_expr seq) (dump_block body)
  | Defer (b, _) -> Printf.sprintf "(defer %s)" (dump_block b)
  | Do { body; catches; _ } ->
      let dc (c : catch_clause) =
        let p = match c.cpat with Some (e, k) -> Printf.sprintf "%s.%s " e k | None -> "" in
        Printf.sprintf "(catch %s%s)" p (dump_block c.cbody)
      in
      Printf.sprintf "(do %s %s)" (dump_block body) (String.concat " " (List.map dc catches))

and dump_block (stmts : stmt list) : string =
  Printf.sprintf "(%s)" (String.concat " " (List.map dump_stmt stmts))

let dump_param (p : param) : string = Printf.sprintf "%s:%s" p.pname p.ptype

let dump_func (f : func_decl) : string =
  let ps = String.concat " " (List.map dump_param f.params) in
  let ret = match f.ret with Some r -> Printf.sprintf "-> %s " r | None -> "" in
  let th = if f.throws then "throws " else "" in
  Printf.sprintf "(func %s (%s) %s%s%s)" f.fname ps th ret (dump_block f.body)

let dump_field (f : field) : string = Printf.sprintf "%s:%s" f.fld_name f.fld_ty
let dump_struct (s : struct_decl) : string =
  let conf = if s.sconforms = [] then "" else ":" ^ String.concat "," s.sconforms ^ " " in
  let methods = if s.smethods = [] then "" else " " ^ String.concat " " (List.map dump_func s.smethods) in
  Printf.sprintf "(struct %s %s(%s)%s)" s.sname conf (String.concat " " (List.map dump_field s.sfields)) methods

let dump_req (r : proto_req) : string =
  let ps = String.concat " " (List.map dump_param r.rparams) in
  let ret = match r.rret with Some t -> " -> " ^ t | None -> "" in
  Printf.sprintf "(req %s (%s)%s)" r.rname ps ret
let dump_proto (p : proto_decl) : string =
  Printf.sprintf "(protocol %s %s)" p.pname (String.concat " " (List.map dump_req p.reqs))

let dump_case (c : enum_case) : string =
  if c.payload = [] then c.cname else Printf.sprintf "%s(%s)" c.cname (String.concat "," c.payload)
let dump_enum (e : enum_decl) : string =
  let raw = if e.is_error then ":Error " else match e.eraw with Some r -> ":" ^ r ^ " " | None -> "" in
  Printf.sprintf "(enum %s %s(%s))" e.ename raw (String.concat " " (List.map dump_case e.ecases))

let dump_class (c : class_decl) : string =
  let sup = match c.csuper with Some s -> ":" ^ s ^ " " | None -> "" in
  let init = match c.cinit with Some i -> " " ^ dump_func i | None -> "" in
  let ms = String.concat " " (List.map (fun (ov, m) -> (if ov then "(override " else "") ^ dump_func m ^ (if ov then ")" else "")) c.cmethods) in
  Printf.sprintf "(class %s %s(%s)%s %s)" c.cname sup (String.concat " " (List.map dump_field c.cfields)) init ms

let dump_item = function
  | IFunc f -> dump_func f
  | IStruct s -> dump_struct s
  | IEnum e -> dump_enum e
  | IProto p -> dump_proto p
  | IClass c -> dump_class c
  | IStmt s -> dump_stmt s

let dump_program (p : program) : string = String.concat "\n" (List.map dump_item p.items)
