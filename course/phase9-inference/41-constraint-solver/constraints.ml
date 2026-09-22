(* The constraint system — a *contract* (fully written). What `csgen.ml` produces and
   `solver.ml` consumes.

   Concept 05's checker decided every node the moment it reached it. That works because its
   rules are local: an operator looks at two operand types and answers. A constraint-based
   checker does the opposite — it writes down what must be TRUE and postpones every decision,
   so a fact learned at the far end of an expression can settle a question asked at the near
   end. That is the whole difference, and everything below follows from it.

   Design oracle: swift/include/swift/Sema/Constraint.h (the constraint kinds),
   swift/lib/Sema/CSGen.cpp (generation), CSSolver.cpp (solving), CSApply.cpp (writing the
   answer back). swift/docs/TypeChecker.md is the design document. *)

(* A type as the solver sees it: either something known, or an UNKNOWN to be solved for.
   Concept 05's `Types.ty` had no such case, which is exactly why it had to decide early. *)
type ty =
  | Con of Types.ty (* a concrete type: Int, Bool, Double, String *)
  | Var of int (* $T0, $T1, … — swiftc spells these $T0 too *)

let string_of_ty = function
  | Con t -> Types.string_of_ty t
  | Var n -> Printf.sprintf "$T%d" n

(* Swift's literals are POLYMORPHIC: `1` is anything `ExpressibleByIntegerLiteral`, and only
   the context decides which. Concept 05 modelled that with `is_int_literal`, a predicate that
   WALKED the expression to ask "could this whole subtree have been a Double?". Here it is a
   constraint on one type variable instead — the walk disappears, and so does its cost. *)
type literal_kind =
  | Int_literal (* Int or Double, defaulting to Int *)
  | Double_literal (* Double only, in this subset *)

let string_of_literal_kind = function
  | Int_literal -> "ExpressibleByIntegerLiteral"
  | Double_literal -> "ExpressibleByFloatLiteral"

(* The constraints themselves. Three kinds is enough for this subset; swiftc has about forty
   (Constraint.h's `ConstraintKind`), most of them about conformance and subtyping. *)
type t =
  | Equal of ty * ty * Token.span
      (* these two types are the same. The workhorse — swiftc's `Bind`/`Equal`. *)
  | Literal of ty * literal_kind * Token.span
      (* this type must be one a literal of that kind can take. swiftc words it as conformance
         to a protocol, and resolves it the same way: try the default first. *)
  | Disjunction of disjunction
      (* EXACTLY ONE of these alternatives must hold. This is where overloading lives, and it
         is the only constraint that cannot be solved by looking at it — it has to be SEARCHED,
         which is where the exponent in "exponential in the worst case" comes from. *)

and disjunction = {
  what : string; (* the overloaded name, for diagnostics: "+", "abs" *)
  is_operator : bool; (* an operator and a call are reported with different wordings *)
  args : ty list; (* the operands' types — kept so a FAILED search can say what it saw *)
  result : ty;
  choices : choice list;
  dspan : Token.span;
}

and choice = {
  label : string; (* "(Int, Int) -> Int", printed in --emit-constraints *)
  index : int; (* WHICH declaration this is, in source order — csapply records it *)
  implies : t list; (* the constraints this alternative asserts *)
}

let rec string_of_constraint = function
  | Equal (a, b, _) -> Printf.sprintf "%s == %s" (string_of_ty a) (string_of_ty b)
  | Literal (a, k, _) ->
      Printf.sprintf "%s : %s" (string_of_ty a) (string_of_literal_kind k)
  | Disjunction { what; choices; _ } ->
      Printf.sprintf "%s is one of {%s}" what
        (String.concat " | "
           (List.map
              (fun c ->
                Printf.sprintf "%s [%s]" c.label
                  (String.concat ", " (List.map string_of_constraint c.implies)))
              choices))

(* --- overload sets ----------------------------------------------------------------------
   A signature, and the machinery for an overloaded NAME. Concept 07 kept one signature per
   name and reported a second declaration as `invalid redeclaration`. Swift does not: several
   functions may share a name as long as their signatures differ, and picking between them is
   the job this concept exists to do. *)

type signature = { params : Types.ty list; result : Types.ty }

let show_signature (s : signature) : string =
  Printf.sprintf "(%s) -> %s"
    (String.concat ", " (List.map Types.string_of_ty s.params))
    (Types.string_of_ty s.result)

let same_signature (a : signature) (b : signature) : bool =
  (* Swift distinguishes overloads by their FULL type, return included — `f() -> Int` and
     `f() -> Double` are two functions. Only an exact repeat is a redeclaration. *)
  Types.equal a.result b.result
  && List.length a.params = List.length b.params
  && List.for_all2 Types.equal a.params b.params

(* The operators, as overload sets. `+` is the interesting one: three choices, and which
   applies is not decidable from the operands alone when both are literals. *)
let operator_overloads (op : Ast.binop) : signature list =
  let num t = { params = [ t; t ]; result = t } in
  let cmp t = { params = [ t; t ]; result = Types.TBool } in
  match op with
  | Ast.Add -> [ num Types.TInt; num Types.TDouble; num Types.TString ]
  | Ast.Sub | Ast.Mul | Ast.Div -> [ num Types.TInt; num Types.TDouble ]
  | Ast.Mod -> [ num Types.TInt ] (* no `%` on Double, as in Swift *)
  | Ast.And | Ast.Or -> [ num Types.TBool ]
  | Ast.Eq | Ast.Ne ->
      [ cmp Types.TInt; cmp Types.TDouble; cmp Types.TString; cmp Types.TBool ]
  | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge ->
      [ cmp Types.TInt; cmp Types.TDouble; cmp Types.TString ]
