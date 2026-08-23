(* Sema — concept 05 (skeleton): the bidirectional type checker.

   You implement the TODO(05) holes. The two judgments, mutually recursive:
     infer e        -> ty        synthesize a type (no expectation)
     check_expr e t -> unit      check e against an expected type t (pushes t down)

   The one coercion is Swift's `ExpressibleByIntegerLiteral`: an *integer literal*
   (recursively, an arithmetic expression of integer literals) may take type Double when a
   Double is expected — so `let d: Double = 1 + 2` works, but `let d: Double = i` (i: Int)
   does not. Full literal flexibility is a constraint-solver job (Phase 5); we special-case
   the common shapes.

   Reference: solution/sema.ml. *)

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  let env : (string, Types.ty * bool) Hashtbl.t = Hashtbl.create 16 in
  let err span msg = Diagnostics.error diags span msg in
  ignore env;
  ignore err;
  ignore prog;
  (* TODO(05): the two judgments — `infer e -> ty` and `check_expr e expected -> unit` — the
     `unify` they share, and `check_stmt` over the program. The one coercion is the literal
     flexibility described in the header. Every diagnostic here is compared against swiftc's
     wording by the tests, so match it exactly. Walk-through: §3. *)
  failwith "TODO(05): implement the bidirectional type checker in sema.ml"
