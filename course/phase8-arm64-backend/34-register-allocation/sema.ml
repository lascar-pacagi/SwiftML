(* sema (given carry-forward) — concept 31 adds Array/String. *)

let check (prog : Ast.program) (diags : Diagnostics.sink) : unit =
  let env : (string * (Types.ty * bool)) list ref = ref [] in
  let loop_depth = ref 0 in
  let current_ret : Types.ty option ref = ref None in
  let funcs : (string, Types.ty list * Types.ty) Hashtbl.t = Hashtbl.create 16 in
  let structs : (string, Types.struct_layout) Hashtbl.t = Hashtbl.create 16 in
  let enums : (string, Types.enum_layout) Hashtbl.t = Hashtbl.create 16 in
  (* concept 21: protocol layouts, per-struct method signatures, and which struct we are
     INSIDE (so method bodies can use `self`, bare field names, and bare method calls) *)
  let protos : (string, Types.proto_layout) Hashtbl.t = Hashtbl.create 16 in
  (* concept 22: the type parameters in scope while checking a generic function's body, and
     the signature table for generic functions (kept separate from `funcs`: their parameter
     types mention TVar and their calls need INFERENCE, not just checking) *)
  let current_generics : (string * string) list ref = ref [] in
  (* error handling — concept 30 *)
  let throwing : (string, unit) Hashtbl.t = Hashtbl.create 16 in   (* throwing function names *)
  let error_enums : (string, unit) Hashtbl.t = Hashtbl.create 8 in (* enums declared `: Error` *)
  let current_throws = ref false in (* the function being checked is declared `throws` *)
  let do_depth = ref 0 in           (* >0 inside a do-block body (can handle locally) *)
  let in_try = ref false in         (* checking the operand of a `try` *)
  let can_handle () = !current_throws || !do_depth > 0 in
  (* concept 29: the env length at each enclosing closure's entry — a binding OLDER than the
     innermost floor is a CAPTURE (by value in v0: assignment to it is rejected, and managed
     types can't be captured at all — the context would need retain/destroy machinery) *)
  let closure_floors : int list ref = ref [] in
  let binding_is_captured name =
    match !closure_floors with
    | [] -> false
    | floor :: _ -> (
        let rec idx i = function
          | (n, _) :: _ when n = name -> Some i
          | _ :: tl -> idx (i + 1) tl
          | [] -> None
        in
        match idx 0 !env with
        | Some i -> i >= List.length !env - floor
        | None -> false)
  in
  (* concept 25: class layouts (fields incl. inherited, vtable in slot order), and the class
     whose init/method body we're inside (with in_init: field writes + super.init allowed) *)
  let classes : (string, Types.class_layout) Hashtbl.t = Hashtbl.create 16 in
  let current_class : string option ref = ref None in
  let in_init = ref false in
  let super_called = ref false in
  let assigned_fields : (string, unit) Hashtbl.t = Hashtbl.create 8 in
  let rec is_subclass d c =
    d = c
    || match Hashtbl.find_opt classes d with
       | Some { Types.cl_super = Some s; _ } -> is_subclass s c
       | _ -> false
  in
  ignore is_subclass;
  (* the class whose declared init a constructor call runs: own init, else the nearest
     superclass's (Swift inherits initializers when a subclass adds no stored properties) *)
  let rec init_owner cn =
    if Hashtbl.mem funcs (cn ^ ".init") then Some cn
    else match Hashtbl.find_opt classes cn with
      | Some { Types.cl_super = Some s; _ } -> init_owner s
      | _ -> None
  in
  let gfuncs : (string, (string * string) list * Types.ty list * Types.ty) Hashtbl.t = Hashtbl.create 16 in
  let methods : (string, (string * Types.ty list * Types.ty) list) Hashtbl.t = Hashtbl.create 16 in
  let current_self : string option ref = ref None in
  let method_sig sname m = Option.bind (Hashtbl.find_opt methods sname) (fun ms -> List.find_map (fun (n, ps, r) -> if n = m then Some (ps, r) else None) ms) in
  let struct_conforms sname pname =
    match Hashtbl.find_opt protos pname with
    | None -> false
    | Some pl ->
        List.for_all
          (fun (rn, rps, rret) -> match method_sig sname rn with Some (ps, r) -> ps = rps && r = rret | None -> false)
          pl.Types.pl_reqs
  in
  let field_of_self x =
    match (!current_self, !current_class) with
    | Some sname, _ -> Option.bind (Hashtbl.find_opt structs sname) (fun sl -> Types.field_type sl x)
    | None, Some cname -> Option.bind (Hashtbl.find_opt classes cname) (fun cl -> Types.cfield_type cl x)
    | None, None -> None
  in
  let err span msg = Diagnostics.error diags span msg in
  let lookup x = List.assoc_opt x !env in
  let bind name v = env := (name, v) :: !env in
  let in_scope (f : unit -> unit) = let saved = !env in f (); env := saved in
  (* resolve a written type name: a builtin (Int/Bool/…), a declared struct, or a declared enum *)
  let rec resolve_opt name =
    (* a written FUNCTION type "(T1,T2)->R" (canonically encoded by the parser) — concept 29 *)
    match Types.split_fn_written name with
    | Some (ps, ret) -> (
        let pts = List.map resolve_opt ps and rt = resolve_opt ret in
        if List.for_all Option.is_some pts && Option.is_some rt then
          Some (Types.TFunc (List.map Option.get pts, Option.get rt))
        else None)
    | None ->
    (* a written ARRAY type "[T]" (canonically encoded by the parser) — concept 31 *)
    match Types.split_array_written name with
    | Some el -> Option.map (fun t -> Types.TArray t) (resolve_opt el)
    | None ->
    (* a trailing `?` makes it an optional of the base type — concept 13 *)
    if String.length name > 0 && name.[String.length name - 1] = '?' then
      Option.map (fun t -> Types.TOptional t) (resolve_opt (String.sub name 0 (String.length name - 1)))
    else
      match Types.of_name name with
      | Some t -> Some t
      | None ->
          if Hashtbl.mem structs name then Some (Types.TStruct name)
          else if Hashtbl.mem enums name then Some (Types.TEnum name)
          else if Hashtbl.mem protos name then Some (Types.TProto name) (* `P`/`any P` — concept 21 *)
          else if Hashtbl.mem classes name then Some (Types.TClass name) (* concept 25 *)
          else (
            (* a type parameter of the enclosing generic function — concept 22 *)
            match List.assoc_opt name !current_generics with
            | Some c -> Some (Types.TVar (name, c))
            | None -> None)
  in
  let resolve_silent name = Option.value (resolve_opt name) ~default:Types.TInt in
  (* concept-31 v0 scope: the array buffer is a homogeneous i64 store, so only `[Int]` is fully
     correct (a `[String]`/`[Bool]` would need a word-generic buffer — that's exercise 1). We
     reject other element types up front rather than miscompile them. *)
  let check_array_elt span = function
    | Types.TArray Types.TInt -> ()
    | Types.TArray el ->
        err span
          (Printf.sprintf
             "arrays of '%s' are not supported in this subset (only '[Int]'; element-generic \
              buffers are this concept's exercise)"
             (Types.string_of_ty el))
    | _ -> ()
  in
  let resolve_ty span name =
    match resolve_opt name with
    | Some (Types.TOptional t) when (match t with Types.TClass _ -> true | _ -> false) ->
        err span "optional class references are not supported in this subset";
        Types.TOptional t
    | Some t -> check_array_elt span t; t
    | None ->
        err span (Printf.sprintf "cannot find type '%s' in scope" name);
        Types.TInt
  in

  let rec is_int_literal = function
    | Ast.Int_lit _ -> true
    | Ast.Unary (Ast.Neg, e, _) -> is_int_literal e
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div | Ast.Mod), a, b, _) ->
        is_int_literal a && is_int_literal b
    | _ -> false
  in
  let unify l tl r tr : Types.ty option =
    if Types.equal tl tr then Some tl
    else if is_int_literal l && tr = Types.TDouble then Some Types.TDouble
    else if is_int_literal r && tl = Types.TDouble then Some Types.TDouble
    else None
  in
  let rec infer (e : Ast.expr) : Types.ty =
    match e with
    | Ast.Int_lit _ -> Types.TInt
    | Ast.Double_lit _ -> Types.TDouble
    | Ast.Bool_lit _ -> Types.TBool
    | Ast.String_lit _ -> Types.TString
    | Ast.Var (x, span) -> (
        match lookup x with
        | Some ((Types.TClass _ | Types.TFunc _) as t, _) when binding_is_captured x ->
            err span
              (Printf.sprintf "cannot capture '%s' in this subset (closure captures are plain values)" x);
            t
        | Some (t, _) -> t
        | None -> (
            (* inside a method, a bare name may be a stored property (implicit self) — 21 *)
            match field_of_self x with
            | Some ft ->
                if !closure_floors <> [] then
                  err span
                    (Printf.sprintf "cannot capture property '%s' implicitly; bind it first: let %s = self.%s" x x x);
                ft
            | None ->
                (* a plain named function used as a VALUE: `let g = dbl` (concept 29) *)
                if Hashtbl.mem funcs x then
                  let ptys, ret = Hashtbl.find funcs x in
                  Types.TFunc (ptys, ret)
                else if Hashtbl.mem gfuncs x then (
                  err span (Printf.sprintf "generic function '%s' cannot be used as a value in this subset" x);
                  Types.TInt)
                else (
                  err span (Printf.sprintf "cannot find '%s' in scope" x);
                  Types.TInt)))
    | Ast.Unary (Ast.Neg, e0, span) ->
        let t = infer e0 in
        if Types.is_numeric t then t
        else (
          err span
            (Printf.sprintf "unary operator '-' cannot be applied to operand of type '%s'"
               (Types.string_of_ty t));
          t)
    | Ast.Binary (op, l, r, span) -> infer_binary op l r span
    | Ast.Call (f, args, span) -> infer_call f args span
    (* `E.case` — a no-payload enum case names a value of the enum type (concept 11) *)
    | Ast.Member (Ast.Var (tn, _), case, span) when Hashtbl.mem enums tn -> (
        let el = Hashtbl.find enums tn in
        match Types.case_payload el case with
        | Some [] -> Types.TEnum tn
        | Some _ ->
            err span (Printf.sprintf "enum case '%s.%s' requires arguments" tn case);
            Types.TEnum tn
        | None -> err span (Printf.sprintf "type '%s' has no case '%s'" tn case); Types.TEnum tn)
    | Ast.Member (e0, fld, span) -> (
        match infer e0 with
        | Types.TStruct sn -> (
            match Hashtbl.find_opt structs sn with
            | Some sl -> (
                match Types.field_type sl fld with
                | Some ft -> ft
                | None ->
                    err span (Printf.sprintf "value of type '%s' has no member '%s'" sn fld);
                    Types.TInt)
            | None -> Types.TInt)
        (* `a.count` on an Array or a String — the element/byte count (concept 31) *)
        | (Types.TArray _ | Types.TString) when fld = "count" -> Types.TInt
        | (Types.TArray _ | Types.TString) when fld = "isEmpty" -> Types.TBool
        (* `e.rawValue` on a raw-value enum yields its Int raw value (concept 11) *)
        | Types.TEnum en when fld = "rawValue" && (Hashtbl.find enums en).Types.el_raw -> Types.TInt
        | Types.TClass cn -> (
            match Option.bind (Hashtbl.find_opt classes cn) (fun cl -> Types.cfield_type cl fld) with
            | Some ft -> ft
            | None ->
                err span (Printf.sprintf "value of type '%s' has no member '%s'" cn fld);
                Types.TInt)
        (* an existential exposes ONLY its protocol's requirements — and v0 has no property
           requirements, so any plain member access is an error (matches swiftc) — 21 *)
        | Types.TProto pn ->
            err span (Printf.sprintf "value of type 'any %s' has no member '%s'" pn fld);
            Types.TInt
        | t ->
            err span (Printf.sprintf "value of type '%s' has no member '%s'" (Types.string_of_ty t) fld);
            Types.TInt)
    (* `E.case(args)` — a payload-carrying enum case (concept 11) *)
    | Ast.Method_call (Ast.Var (tn, _), case, args, span) when Hashtbl.mem enums tn -> (
        let el = Hashtbl.find enums tn in
        match Types.case_payload el case with
        | Some tys ->
            let exprs = List.map snd args in
            if List.length tys <> List.length exprs then
              err span
                (Printf.sprintf "enum case '%s.%s' expects %d associated value(s) but %d given" tn case
                   (List.length tys) (List.length exprs))
            else List.iter2 (fun e t -> check_expr e t) exprs tys;
            Types.TEnum tn
        | None -> err span (Printf.sprintf "type '%s' has no case '%s'" tn case); Types.TEnum tn)
    (* `super.init(args)` — only inside a subclass initializer (concept 25) *)
    | Ast.Method_call (Ast.Var ("super", _), "init", args, span) -> (
        let exprs = List.map snd args in
        match (!current_class, !in_init) with
        | Some cn, true -> (
            match Option.bind (Hashtbl.find_opt classes cn) (fun cl -> cl.Types.cl_super) with
            | Some sup -> (
                super_called := true;
                match Hashtbl.find_opt funcs (sup ^ ".init") with
                | Some (ptys, _) ->
                    let np = List.length ptys and na = List.length exprs in
                    if np <> na then
                      err span (Printf.sprintf "initializer of '%s' expects %d argument(s) but %d given" sup np na)
                    else List.iter2 (fun a t -> check_expr a t) exprs ptys;
                    Types.TVoid
                | None -> List.iter (fun a -> ignore (infer a)) exprs; Types.TVoid)
            | None ->
                err span (Printf.sprintf "'super' members cannot be referenced: '%s' has no superclass" cn);
                Types.TVoid)
        | _ ->
            err span "'super.init' can only be called inside an initializer";
            List.iter (fun a -> ignore (infer a)) exprs;
            Types.TVoid)
    (* `recv.m(args)` — a METHOD call (concept 21). On a concrete struct it resolves statically
       against the struct's methods; on an existential (`any P`) it must be one of P's
       requirements and will dispatch through the witness table. Args are positional. *)
    | Ast.Method_call (e0, m, args, span) -> (
        let exprs = List.map snd args in
        let check_args what ptys =
          let np = List.length ptys and na = List.length exprs in
          if np <> na then err span (Printf.sprintf "%s expects %d argument(s) but %d given" what np na)
          else List.iter2 (fun a t -> check_expr a t) exprs ptys
        in
        match infer e0 with
        (* Array methods: `append` (concept 31) + the higher-order trio (concept 32). map/filter/
           reduce each take a CLOSURE and walk the buffer — the payoff that unites closures (29)
           with containers (31). *)
        | Types.TArray el -> (
            match (m, exprs) with
            | "append", [ _ ] -> check_args "method 'append'" [ el ]; Types.TVoid
            (* `a.map { (x: E) -> R in … }` : apply the closure to each element -> `[R]` *)
            | "map", [ f ] -> (
                match infer f with
                | Types.TFunc ([ p ], r) when Types.equal p el ->
                    check_array_elt span (Types.TArray r); Types.TArray r
                | tf ->
                    err span
                      (Printf.sprintf "map expects a closure '(%s) -> R', found '%s'"
                         (Types.string_of_ty el) (Types.string_of_ty tf));
                    Types.TArray el)
            (* `a.filter { (x: E) -> Bool in … }` : keep elements where the closure is true -> `[E]` *)
            | "filter", [ f ] -> (
                match infer f with
                | Types.TFunc ([ p ], Types.TBool) when Types.equal p el -> Types.TArray el
                | tf ->
                    err span
                      (Printf.sprintf "filter expects a closure '(%s) -> Bool', found '%s'"
                         (Types.string_of_ty el) (Types.string_of_ty tf));
                    Types.TArray el)
            (* `a.reduce(init) { (acc: R, x: E) -> R in … }` : fold left -> `R` *)
            | "reduce", [ init; f ] -> (
                let r = infer init in
                match infer f with
                | Types.TFunc ([ a; e ], r2)
                  when Types.equal a r && Types.equal e el && Types.equal r2 r ->
                    r
                | tf ->
                    err span
                      (Printf.sprintf "reduce expects '(%s, %s) -> %s', found '%s'"
                         (Types.string_of_ty r) (Types.string_of_ty el) (Types.string_of_ty r)
                         (Types.string_of_ty tf));
                    r)
            | _ ->
                err span (Printf.sprintf "value of type '%s' has no member '%s'" (Types.string_of_ty (Types.TArray el)) m);
                List.iter (fun a -> ignore (infer a)) exprs;
                Types.TVoid)
        | Types.TStruct sn -> (
            match method_sig sn m with
            | Some (ptys, ret) -> check_args (Printf.sprintf "method '%s'" m) ptys; ret
            | None ->
                err span (Printf.sprintf "value of type '%s' has no member '%s'" sn m);
                List.iter (fun a -> ignore (infer a)) exprs;
                Types.TInt)
        | Types.TProto pn -> (
            match Option.bind (Hashtbl.find_opt protos pn) (fun pl -> Types.req_sig pl m) with
            | Some (ptys, ret) -> check_args (Printf.sprintf "method '%s'" m) ptys; ret
            | None ->
                err span (Printf.sprintf "value of type 'any %s' has no member '%s'" pn m);
                List.iter (fun a -> ignore (infer a)) exprs;
                Types.TInt)
        (* a class method call — DYNAMIC dispatch through the vtable (concept 25) *)
        | Types.TClass cn -> (
            match Option.bind (Hashtbl.find_opt classes cn) (fun cl -> Types.vsig cl m) with
            | Some (ptys, ret) -> check_args (Printf.sprintf "method '%s'" m) ptys; ret
            | None ->
                err span (Printf.sprintf "value of type '%s' has no member '%s'" cn m);
                List.iter (fun a -> ignore (infer a)) exprs;
                Types.TInt)
        (* a value of type parameter T exposes its CONSTRAINT's requirements — concept 22 *)
        | Types.TVar (tn, pn) -> (
            match Option.bind (Hashtbl.find_opt protos pn) (fun pl -> Types.req_sig pl m) with
            | Some (ptys, ret) -> check_args (Printf.sprintf "method '%s'" m) ptys; ret
            | None ->
                err span (Printf.sprintf "value of type '%s' has no member '%s'" tn m);
                List.iter (fun a -> ignore (infer a)) exprs;
                Types.TInt)
        | t ->
            err span (Printf.sprintf "value of type '%s' has no member '%s'" (Types.string_of_ty t) m);
            List.iter (fun a -> ignore (infer a)) exprs;
            Types.TInt)
    (* optionals — concept 13 *)
    | Ast.Nil span ->
        err span "'nil' requires a contextual type";
        Types.TOptional Types.TInt
    | Ast.Force_unwrap (e0, span) -> (
        match infer e0 with
        | Types.TOptional t -> t
        | t ->
            err span (Printf.sprintf "cannot force-unwrap a non-optional value of type '%s'" (Types.string_of_ty t));
            t)
    (* `e as? T` / `e as! T` — concept 23: a DYNAMIC cast on an existential. The static types
       can't decide it; the runtime compares witness tables. `as?` yields `T?`; `as!` yields
       `T` (and aborts at runtime on mismatch, like swiftc). Casting to a type that cannot
       conform is legal but warned — it always fails. *)
    (* `{ (x: Int) -> Int in expr }` — concept 29. Parameters are explicitly typed, so the
       closure's type is self-describing; the single-expression body checks in a scope of the
       params layered over the enclosing env (reads of older bindings CAPTURE them). *)
    | Ast.Closure (params, ret, body, span) ->
        let ptys = List.map (fun (pr : Ast.param) -> resolve_ty span pr.Ast.ptype) params in
        let saved = !env and saved_floors = !closure_floors in
        closure_floors := List.length !env :: !closure_floors;
        List.iter2 (fun (pr : Ast.param) t -> bind pr.Ast.pname (t, false)) params ptys;
        let bty = infer body in
        let rty =
          match ret with
          | Some n ->
              let rt = resolve_ty span n in
              check_expr body rt;
              rt
          | None -> bty
        in
        env := saved;
        closure_floors := saved_floors;
        Types.TFunc (ptys, rty)
    (* `try e` / `try? e` / `try! e` — concept 30. `try` just marks the call site; `try?`
       turns a throw into nil (T -> T?); `try!` asserts no throw (type unchanged). *)
    | Ast.Try (kind, e0, _) ->
        let saved_try = !in_try in
        in_try := true;
        (* `try!` and `try?` HANDLE the error locally (trap / nil), so calls inside them are in
           a handling context even outside a throwing function — concept 30 *)
        let saved_do = !do_depth in
        (match kind with Ast.TryOptional | Ast.TryForce -> incr do_depth | Ast.TryPlain -> ());
        let t = infer e0 in
        in_try := saved_try;
        do_depth := saved_do;
        (match kind with Ast.TryOptional -> Types.TOptional t | _ -> t)
    | Ast.Cast (e0, tyname, conditional, span) -> (
        let target =
          match resolve_opt tyname with
          | Some (Types.TStruct sn) -> Some sn
          | Some _ ->
              err span (Printf.sprintf "cannot cast to non-struct type '%s' in this subset" tyname);
              None
          | None ->
              err span (Printf.sprintf "cannot find type '%s' in scope" tyname);
              None
        in
        match (infer e0, target) with
        | Types.TProto pn, Some sn ->
            if not (struct_conforms sn pn) then
              Diagnostics.warning diags span
                (Printf.sprintf "cast from 'any %s' to unrelated type '%s' always fails" pn sn);
            if conditional then Types.TOptional (Types.TStruct sn) else Types.TStruct sn
        | t, Some sn ->
            err span
              (Printf.sprintf "cannot cast a value of type '%s' (only existentials support as?/as! in this subset)"
                 (Types.string_of_ty t));
            if conditional then Types.TOptional (Types.TStruct sn) else Types.TStruct sn
        | _, None -> Types.TInt)
    | Ast.Coalesce (a, b, span) -> (
        match infer a with
        | Types.TOptional t -> check_expr b t; t
        | t ->
            err span (Printf.sprintf "left operand of '??' must be optional, found '%s'" (Types.string_of_ty t));
            ignore (infer b);
            t)
    (* ternary `c ? a : b` — condition is Bool, both arms agree on a type = the result type *)
    | Ast.Ternary (c, a, b, _) ->
        check_expr c Types.TBool;
        let t = infer a in
        check_expr b t;
        t
    (* `[a, b, c]` — an array literal (concept 31). All elements must agree on a type, which
       becomes the array's element type. An empty literal `[]` needs a contextual type, which
       `check_expr` supplies; on its own it's an error. *)
    | Ast.Array_lit (es, span) -> (
        match es with
        | [] ->
            err span "empty array literal requires a contextual element type";
            Types.TArray Types.TInt
        | e0 :: rest ->
            let et = infer e0 in
            List.iter (fun e -> check_expr e et) rest;
            check_array_elt span (Types.TArray et);
            Types.TArray et)
    (* `a[i]` — subscript an array by an Int index (concept 31). Yields the element type. *)
    | Ast.Subscript (e0, idx, span) -> (
        check_expr idx Types.TInt;
        match infer e0 with
        | Types.TArray el -> el
        | t ->
            err span (Printf.sprintf "value of type '%s' has no subscripts" (Types.string_of_ty t));
            Types.TInt)
  and infer_binary op l r span : Types.ty =
    (* `opt == nil` / `opt != nil` — compare an optional with the nil literal *)
    match (op, l, r) with
    | (Ast.Eq | Ast.Ne), Ast.Nil _, other | (Ast.Eq | Ast.Ne), other, Ast.Nil _ -> (
        match infer other with
        | Types.TOptional _ -> Types.TBool
        | t -> err span (Printf.sprintf "value of type '%s' cannot be compared with 'nil'" (Types.string_of_ty t)); Types.TBool)
    | _ -> infer_binary_base op l r span
  and infer_binary_base op l r span : Types.ty =
    let tl = infer l and tr = infer r in
    let bad () =
      err span
        (Printf.sprintf "binary operator '%s' cannot be applied to operands of type '%s' and '%s'"
           (Ast.string_of_binop op) (Types.string_of_ty tl) (Types.string_of_ty tr));
      Types.TInt
    in
    match op with
    | Ast.Add -> (
        match unify l tl r tr with
        | Some ((Types.TInt | Types.TDouble) as t) -> t
        | Some Types.TString -> Types.TString
        | _ -> bad ())
    | Ast.Sub | Ast.Mul | Ast.Div -> (
        match unify l tl r tr with Some ((Types.TInt | Types.TDouble) as t) -> t | _ -> bad ())
    | Ast.Mod -> ( match unify l tl r tr with Some Types.TInt -> Types.TInt | _ -> bad ())
    | Ast.Eq | Ast.Ne -> (
        match unify l tl r tr with
        (* a payload-free enum is implicitly Equatable; an associated-value enum needs an explicit
           `: Equatable` conformance (deferred), so swiftc — and we — reject `==` on it *)
        | Some (Types.TEnum en) when Types.has_payload (Hashtbl.find enums en) ->
            err span (Printf.sprintf "type '%s' does not conform to protocol 'Equatable'" en);
            Types.TBool
        (* `==` on two existentials: the concrete types aren't statically known — swiftc rejects
           it (an existential is not Equatable) and so do we — 21 *)
        | Some (Types.TProto pn) ->
            err span (Printf.sprintf "binary operator '==' cannot be applied to two 'any %s' operands" pn);
            Types.TBool
        | Some (Types.TVar (tn, _)) ->
            err span (Printf.sprintf "binary operator '==' cannot be applied to two '%s' operands" tn);
            Types.TBool
        | Some _ -> Types.TBool
        | None -> ignore (bad ()); Types.TBool)
    | Ast.Lt | Ast.Le | Ast.Gt | Ast.Ge -> (
        match unify l tl r tr with
        | Some (Types.TInt | Types.TDouble | Types.TString) -> Types.TBool
        | _ -> ignore (bad ()); Types.TBool)
    | Ast.And | Ast.Or ->
        if tl = Types.TBool && tr = Types.TBool then Types.TBool else (ignore (bad ()); Types.TBool)
  and infer_call f args span : Types.ty =
    (* a LOCAL holding a function value: `g(50)` where g : (Int) -> Int — indirect (29) *)
    match lookup f with
    | Some (Types.TFunc (ptys, ret), _) ->
        let exprs = List.map snd args in
        let np = List.length ptys and na = List.length exprs in
        if np <> na then
          err span (Printf.sprintf "function value '%s' expects %d argument(s) but %d given" f np na)
        else List.iter2 (fun a t -> check_expr a t) exprs ptys;
        if binding_is_captured f && false then ();
        ret
    | _ ->
    if Hashtbl.mem classes f then (
      (* `Counter(10)` — a class CONSTRUCTOR: heap-allocate then run the declared init.
         Arguments check against the init's parameters (positionally, like our funcs). *)
      let exprs = List.map snd args in
      (match Option.bind (init_owner f) (fun o -> Hashtbl.find_opt funcs (o ^ ".init")) with
      | Some (ptys, _) ->
          let np = List.length ptys and na = List.length exprs in
          if np <> na then
            err span (Printf.sprintf "initializer of '%s' expects %d argument(s) but %d given" f np na)
          else List.iter2 (fun a t -> check_expr a t) exprs ptys
      | None ->
          if exprs <> [] then err span (Printf.sprintf "class '%s' has no initializers" f)
          else List.iter (fun a -> ignore (infer a)) exprs);
      Types.TClass f)
    else
    match Hashtbl.find_opt structs f with
    | Some sl -> infer_init f sl args span (* `Point(x: 1, y: 2)` — memberwise initializer *)
    | None when Hashtbl.mem gfuncs f ->
        let generics, ptypes, ret = Hashtbl.find gfuncs f in
        infer_generic_call f generics ptypes ret args span
    | None -> (
        let exprs = List.map snd args in
        match Hashtbl.find_opt funcs f with
        | Some (ptypes, ret) ->
            let np = List.length ptypes and na = List.length exprs in
            if np <> na then
              err span (Printf.sprintf "function '%s' expects %d argument(s) but %d given" f np na)
            else List.iter2 (fun a t -> check_expr a t) exprs ptypes;
            (* a call to a THROWING function must be `try`-marked AND in an error-handling
               context — swiftc's two distinct diagnostics (concept 30) *)
            if Hashtbl.mem throwing f then begin
              if not !in_try then
                err span "call can throw, but it is not marked with 'try' and the error is not handled"
              else if not (can_handle ()) then err span "errors thrown from here are not handled"
            end;
            ret
        | None when !current_class <> None
                    && Option.bind (Hashtbl.find_opt classes (Option.get !current_class))
                         (fun cl -> Types.vsig cl f)
                       <> None ->
            (* bare `m(args)` in a CLASS method = `self.m(args)` — and it DISPATCHES (25) *)
            let cl = Hashtbl.find classes (Option.get !current_class) in
            let ptys, ret = Option.get (Types.vsig cl f) in
            let np = List.length ptys and na = List.length exprs in
            if np <> na then
              err span (Printf.sprintf "method '%s' expects %d argument(s) but %d given" f np na)
            else List.iter2 (fun a t -> check_expr a t) exprs ptys;
            ret
        | None when !current_self <> None && method_sig (Option.get !current_self) f <> None ->
            (* bare `m(args)` inside a method = `self.m(args)` (implicit self) — 21 *)
            let ptys, ret = Option.get (method_sig (Option.get !current_self) f) in
            let np = List.length ptys and na = List.length exprs in
            if np <> na then
              err span (Printf.sprintf "method '%s' expects %d argument(s) but %d given" f np na)
            else List.iter2 (fun a t -> check_expr a t) exprs ptys;
            ret
        | None ->
            if f = "print" then (
              (match exprs with
              | [ a ] -> ignore (infer a)
              | _ ->
                  err span "print(_:) expects exactly one argument";
                  List.iter (fun a -> ignore (infer a)) exprs);
              Types.TVoid)
            else (
              err span (Printf.sprintf "cannot find '%s' in scope" f);
              List.iter (fun a -> ignore (infer a)) exprs;
              Types.TInt))
  (* a call to a GENERIC function — concept 22. Type parameters are INFERRED from the
     arguments: every argument sitting in a `T` position must have the same concrete type
     (else swiftc's "conflicting arguments to generic parameter"), and that type must satisfy
     T's constraint (else "requires that 'X' conform to 'P'"). The result type is the declared
     return with the inferred bindings substituted in. *)
  and infer_generic_call f generics ptypes ret (args : Ast.arg list) span : Types.ty =
    let exprs = List.map snd args in
    let np = List.length ptypes and na = List.length exprs in
    if np <> na then (
      err span (Printf.sprintf "function '%s' expects %d argument(s) but %d given" f np na);
      ret)
    else begin
      let bind : (string * Types.ty) list ref = ref [] in
      List.iter2
        (fun pt a ->
          match pt with
          | Types.TVar (n, _) -> (
              let t = infer a in
              match List.assoc_opt n !bind with
              | None -> bind := (n, t) :: !bind
              | Some t0 ->
                  if not (Types.equal t0 t) then
                    err span
                      (Printf.sprintf "conflicting arguments to generic parameter '%s' ('%s' vs. '%s')" n
                         (Types.string_of_ty t0) (Types.string_of_ty t)))
          | _ -> check_expr a pt)
        ptypes exprs;
      (* every inferred binding must satisfy its constraint *)
      List.iter
        (fun (n, c) ->
          match List.assoc_opt n !bind with
          | Some (Types.TStruct sn) ->
              if not (struct_conforms sn c) then
                err span (Printf.sprintf "global function '%s' requires that '%s' conform to '%s'" f sn c)
          | Some (Types.TVar (_, c')) when c' = c -> () (* a generic calling a generic *)
          | Some t ->
              err span
                (Printf.sprintf "global function '%s' requires that '%s' conform to '%s'" f
                   (Types.string_of_ty t) c)
          | None -> () (* T not used in any parameter — nothing to infer from; v0 leaves it *))
        generics;
      match ret with
      | Types.TVar (n, _) -> ( match List.assoc_opt n !bind with Some t -> t | None -> ret)
      | t -> t
    end
  (* the memberwise initializer: one labeled argument per stored property, in order *)
  and infer_init sn (sl : Types.struct_layout) (args : Ast.arg list) span : Types.ty =
    let fields = sl.Types.sl_fields in
    if List.length args <> List.length fields then
      err span
        (Printf.sprintf "'%s' initializer expects %d argument(s) but %d given" sn (List.length fields)
           (List.length args))
    else
      List.iter2
        (fun (label, value) (fname, ftype) ->
          (match label with
          | Some l when l <> fname ->
              err (Ast.expr_span value)
                (Printf.sprintf "incorrect argument label in call (have '%s:', expected '%s:')" l fname)
          | None -> err (Ast.expr_span value) (Printf.sprintf "missing argument label '%s:' in call" fname)
          | _ -> ());
          check_expr value ftype)
        args fields;
    Types.TStruct sn
  (* checking mode: an optional expected type accepts `nil`, an already-optional value, or — by
     implicit wrapping — a value of the wrapped type (`5 : Int?` becomes `.some(5)`) — concept 13 *)
  and check_expr (e : Ast.expr) (expected : Types.ty) : unit =
    match (e, expected) with
    | Ast.Nil _, Types.TOptional _ -> ()
    | Ast.Nil _, _ ->
        err (Ast.expr_span e)
          (Printf.sprintf "'nil' cannot be used with a non-optional type '%s'" (Types.string_of_ty expected))
    | _, Types.TOptional t ->
        if Types.equal (infer e) expected then () (* already a T? *) else check_expr e t (* wrap T -> T? *)
    (* a concrete value coerces to an existential `any P` exactly when its type conforms to P —
       the implicit existential wrap (the protocol twin of optional wrapping) — concept 21 *)
    | _, Types.TProto pn -> (
        match infer e with
        | Types.TProto pn' when pn' = pn -> () (* already `any P` *)
        | Types.TStruct sn when struct_conforms sn pn -> () (* wrap: SILGen will init_existential *)
        | Types.TStruct sn ->
            err (Ast.expr_span e)
              (Printf.sprintf "argument type '%s' does not conform to expected type '%s'" sn pn)
        | t ->
            err (Ast.expr_span e)
              (Printf.sprintf "cannot convert value of type '%s' to specified type 'any %s'"
                 (Types.string_of_ty t) pn))
    (* a subclass value coerces to any of its superclasses — the upcast (concept 25) *)
    | _, Types.TClass cn -> (
        match infer e with
        | Types.TClass dn when is_subclass dn cn -> ()
        | t ->
            err (Ast.expr_span e)
              (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
                 (Types.string_of_ty t) cn))
    | _ -> check_expr_base e expected
  and check_expr_base (e : Ast.expr) (expected : Types.ty) : unit =
    match e with
    | Ast.Int_lit _ ->
        if expected = Types.TInt || expected = Types.TDouble then ()
        else
          err (Ast.expr_span e)
            (Printf.sprintf "cannot convert value of type 'Int' to specified type '%s'"
               (Types.string_of_ty expected))
    | Ast.Binary ((Ast.Add | Ast.Sub | Ast.Mul | Ast.Div), l, r, _) when Types.is_numeric expected ->
        check_expr l expected;
        check_expr r expected
    | Ast.Binary (Ast.Mod, l, r, _) when expected = Types.TInt ->
        check_expr l Types.TInt;
        check_expr r Types.TInt
    | Ast.Unary (Ast.Neg, e0, _) when Types.is_numeric expected -> check_expr e0 expected
    (* an array literal checked against `[T]` types each element at T — and supplies the element
       type to an otherwise-untyped empty `[]` (concept 31) *)
    | Ast.Array_lit (es, _) when (match expected with Types.TArray _ -> true | _ -> false) ->
        let el = (match expected with Types.TArray el -> el | _ -> assert false) in
        List.iter (fun e -> check_expr e el) es
    | _ ->
        let t = infer e in
        if not (Types.equal t expected) then
          err (Ast.expr_span e)
            (Printf.sprintf "cannot convert value of type '%s' to specified type '%s'"
               (Types.string_of_ty t) (Types.string_of_ty expected))
  in
  (* does a block definitely return on every path? (the "missing return" check) *)
  let rec stmt_returns = function
    | Ast.Return _ -> true
    | Ast.Throw _ -> true (* a throw exits the function, like a return — concept 30 *)
    | Ast.Do { body; catches; _ } ->
        block_returns body && List.for_all (fun (c : Ast.catch_clause) -> block_returns c.Ast.cbody) catches
    | Ast.If { then_blk; else_blk = Some e; _ } -> block_returns then_blk && block_returns e
    (* a switch definitely returns if every case body returns and (the default returns, or — when
       there's no default — the switch is exhaustive, which sema has already guaranteed) *)
    | Ast.Switch { cases; default; _ } ->
        List.for_all (fun (_, body) -> block_returns body) cases
        && (match default with Some d -> block_returns d | None -> true)
    | _ -> false
  and block_returns stmts =
    match List.rev stmts with last :: _ -> stmt_returns last | [] -> false
  in
  let rec check_stmt (s : Ast.stmt) : unit =
    match s with
    | Ast.Let { name; is_var; annot; value; span } ->
        let t =
          match annot with
          | None -> infer value
          | Some tyname -> (
              match resolve_opt tyname with
              | Some t -> check_expr value t; t
              | None -> err span (Printf.sprintf "cannot find type '%s' in scope" tyname); infer value)
        in
        bind name (t, is_var)
    | Ast.Assign { name; value; span } -> (
        if binding_is_captured name then
          err span (Printf.sprintf "cannot assign to '%s': captured by value in this subset" name);
        match lookup name with
        | None when !current_class <> None && field_of_self name <> None ->
            (* classes are REFERENCE types: methods may write stored properties (concept 25);
               inside an init this is also how definite-initialization is satisfied *)
            if !in_init then Hashtbl.replace assigned_fields name ();
            check_expr value (Option.get (field_of_self name))
        | None when field_of_self name <> None ->
            (* a non-`mutating` STRUCT method cannot write a stored property (matches swiftc) — 21 *)
            err span "cannot assign to property: 'self' is immutable";
            check_expr value (Option.get (field_of_self name))
        | None -> err span (Printf.sprintf "cannot find '%s' in scope" name); ignore (infer value)
        | Some (t, is_var) ->
            if not is_var then
              err span (Printf.sprintf "cannot assign to value: '%s' is a 'let' constant" name);
            check_expr value t)
    | Ast.Set_member { obj; field; value; span } -> (
        match lookup obj with
        | Some (Types.TClass cn, _) -> (
            (* reference semantics: fields are assignable through ANY binding, even a `let`
               (the binding is constant, the OBJECT is not) — concept 25 *)
            if obj = "self" && !in_init then Hashtbl.replace assigned_fields field ();
            match Option.bind (Hashtbl.find_opt classes cn) (fun cl -> Types.cfield_type cl field) with
            | Some ft -> check_expr value ft
            | None ->
                err span (Printf.sprintf "value of type '%s' has no member '%s'" cn field);
                ignore (infer value))
        | Some (Types.TStruct _, _) when obj = "self" ->
            err span "cannot assign to property: 'self' is immutable";
            ignore (infer value); ignore field
        | None -> err span (Printf.sprintf "cannot find '%s' in scope" obj); ignore (infer value)
        | Some (Types.TStruct sn, is_var) -> (
            match Option.bind (Hashtbl.find_opt structs sn) (fun sl -> Types.field_type sl field) with
            | Some ft ->
                if not is_var then
                  err span (Printf.sprintf "cannot assign to property '%s': '%s' is a 'let' constant" field obj);
                check_expr value ft
            | None ->
                err span (Printf.sprintf "value of type '%s' has no member '%s'" sn field);
                ignore (infer value))
        | Some (t, _) ->
            err span (Printf.sprintf "value of type '%s' has no member '%s'" (Types.string_of_ty t) field);
            ignore (infer value))
    (* `a[i] = e` — subscript assignment (concept 31). `a` must be a `var` array; index is Int;
       the value is the element type. Mutation triggers copy-on-write at runtime. *)
    | Ast.Set_subscript { arr; index; value; span } -> (
        check_expr index Types.TInt;
        match lookup arr with
        | Some (Types.TArray el, is_var) ->
            if not is_var then
              err span (Printf.sprintf "cannot assign through subscript: '%s' is a 'let' constant" arr);
            check_expr value el
        | Some (t, _) ->
            err span (Printf.sprintf "value of type '%s' has no subscripts" (Types.string_of_ty t));
            ignore (infer value)
        | None -> err span (Printf.sprintf "cannot find '%s' in scope" arr); ignore (infer value))
    | Ast.Expr_stmt (e, _) -> ignore (infer e)
    | Ast.If { cond; then_blk; else_blk; _ } ->
        check_expr cond Types.TBool;
        check_block then_blk;
        Option.iter check_block else_blk
    | Ast.If_let { name; opt; then_blk; else_blk; span } ->
        (* `if let x = opt`: opt must be optional; x is the unwrapped type, bound in the then-block *)
        (match infer opt with
        | Types.TOptional t -> in_scope (fun () -> bind name (t, false); List.iter check_stmt then_blk)
        | t ->
            err span
              (Printf.sprintf "initializer for conditional binding must have Optional type, not '%s'"
                 (Types.string_of_ty t));
            check_block then_blk);
        Option.iter check_block else_blk
    | Ast.While { cond; body; _ } ->
        check_expr cond Types.TBool;
        incr loop_depth; check_block body; decr loop_depth
    | Ast.For { var; lo; hi; body; _ } ->
        check_expr lo Types.TInt;
        check_expr hi Types.TInt;
        incr loop_depth;
        in_scope (fun () -> bind var (Types.TInt, false); List.iter check_stmt body);
        decr loop_depth
    (* `for x in arr { … }` — iterate an array's elements (concept 31). `x` is the element type,
       immutable, bound in the loop body's scope. *)
    | Ast.For_in { var; seq; body; span } -> (
        match infer seq with
        | Types.TArray el ->
            incr loop_depth;
            in_scope (fun () -> bind var (el, false); List.iter check_stmt body);
            decr loop_depth
        | t ->
            err span (Printf.sprintf "type '%s' is not a sequence" (Types.string_of_ty t));
            check_block body)
    | Ast.Switch { subject; cases; default; span } -> check_switch subject cases default span
    | Ast.Break span -> if !loop_depth = 0 then err span "'break' is only allowed inside a loop"
    | Ast.Continue span -> if !loop_depth = 0 then err span "'continue' is only allowed inside a loop"
    | Ast.Return (eo, span) -> (
        match !current_ret with
        | None -> err span "'return' invalid outside of a func"
        | Some rt -> (
            match eo with
            | Some e ->
                if rt = Types.TVoid then
                  err span "unexpected non-void return value in void function"
                else check_expr e rt
            | None ->
                if rt <> Types.TVoid then err span "non-void function should return a value"))
    | Ast.Throw (e, span) ->
        (* the thrown value must be an Error enum, and we must be able to handle/propagate *)
        (match infer e with
        | Types.TEnum en when Hashtbl.mem error_enums en -> ()
        | t -> err span (Printf.sprintf "thrown expression type '%s' does not conform to 'Error'" (Types.string_of_ty t)));
        if not (can_handle ()) then
          err span "error is not handled because the enclosing function is not declared 'throws'"
    | Ast.Defer (body, _) -> check_block body
    | Ast.Do { body; catches; span } ->
        incr do_depth;
        check_block body;
        decr do_depth;
        List.iter
          (fun (c : Ast.catch_clause) ->
            (match c.Ast.cpat with
            | Some (en, cs) ->
                if not (Hashtbl.mem error_enums en) then
                  err span (Printf.sprintf "'%s' is not an error type" en)
                else (
                  match Hashtbl.find_opt enums en with
                  | Some el when Types.case_index el cs <> None -> ()
                  | _ -> err span (Printf.sprintf "type '%s' has no case '%s'" en cs))
            | None -> ());
            check_block c.Ast.cbody)
          catches
  (* type-check a `switch`: each pattern is checked against the subject; an enum-case pattern
     binds the case's associated values into the body scope; then EXHAUSTIVENESS (all enum cases
     covered, or a `default`). Mirrors swiftc's TypeCheckSwitchStmt. *)
  and check_switch subject cases default span : unit =
    match infer subject with
    | Types.TEnum en ->
        let el = Hashtbl.find enums en in
        let covered = ref [] in
        List.iter
          (fun (pat, body) ->
            match pat with
            | Ast.PEnumCase (cname, bindings) -> (
                match Types.case_payload el cname with
                | Some tys ->
                    covered := cname :: !covered;
                    let nb = List.length bindings and nt = List.length tys in
                    if nb <> nt then
                      err span
                        (Printf.sprintf "pattern '.%s' binds %d value(s) but case '%s' has %d associated value(s)"
                           cname nb cname nt);
                    in_scope (fun () ->
                        if nb = nt then
                          List.iter2
                            (fun b t -> match b with Ast.Bind x -> bind x (t, false) | Ast.Ignore -> ())
                            bindings tys;
                        List.iter check_stmt body)
                | None ->
                    err span (Printf.sprintf "type '%s' has no case '%s'" en cname);
                    check_block body)
            | Ast.PInt _ ->
                err span (Printf.sprintf "expression pattern of type 'Int' cannot match values of type '%s'" en);
                check_block body)
          cases;
        Option.iter check_block default;
        if default = None then begin
          let missing = List.filter (fun (c, _) -> not (List.mem c !covered)) el.Types.el_cases in
          if missing <> [] then err span "switch must be exhaustive"
        end
    | Types.TInt ->
        List.iter
          (fun (pat, body) ->
            (match pat with
            | Ast.PInt _ -> ()
            | Ast.PEnumCase (c, _) -> err span (Printf.sprintf "enum case '.%s' cannot match values of type 'Int'" c));
            check_block body)
          cases;
        Option.iter check_block default;
        if default = None then err span "switch must be exhaustive"
    | t -> err span (Printf.sprintf "cannot 'switch' over a value of type '%s'" (Types.string_of_ty t))
  and check_block (stmts : Ast.stmt list) : unit = in_scope (fun () -> List.iter check_stmt stmts) in

  (* check one function body: a fresh scope with the parameters; then "missing return".
     With [self_of] = Some S this is a METHOD of struct S: `self : S` is bound (immutably),
     and bare field/method names resolve through implicit self (concept 21). *)
  let check_func ?(self_of : string option) ?(class_of : string option) ?(init = false)
      (f : Ast.func_decl) : unit =
    let saved_generics = !current_generics in
    List.iter
      (fun (n, c) ->
        match c with
        | Some c ->
            if not (Hashtbl.mem protos c) then
              err f.Ast.fspan (Printf.sprintf "cannot find type '%s' in scope" c)
            else current_generics := (n, c) :: !current_generics
        | None ->
            (* v0: every type parameter needs a protocol constraint (an unconstrained T has no
               usable representation without boxing — see the explainer/exercises) *)
            err f.Ast.fspan
              (Printf.sprintf "type parameter '%s' needs a protocol constraint in this subset (write '<%s: SomeProtocol>')" n n))
      f.Ast.generics;
    let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_ty f.Ast.fspan n in
    let saved_env = !env and saved_ret = !current_ret and saved_self = !current_self in
    env := [];
    current_ret := Some ret;
    current_self := self_of;
    let saved_class = !current_class and saved_init = !in_init and saved_super = !super_called in
    let saved_throws = !current_throws in
    current_throws := f.Ast.throws;
    current_class := class_of;
    in_init := init;
    super_called := false;
    if init then Hashtbl.reset assigned_fields;
    (match self_of with Some sname -> bind "self" (Types.TStruct sname, false) | None -> ());
    (match class_of with Some cname -> bind "self" (Types.TClass cname, false) | None -> ());
    List.iter
      (fun (pr : Ast.param) -> bind pr.Ast.pname (resolve_ty f.Ast.fspan pr.Ast.ptype, false))
      f.Ast.params;
    List.iter check_stmt f.Ast.body;
    env := saved_env;
    current_ret := saved_ret;
    current_self := saved_self;
    (* definite initialization (v0): every OWN stored property assigned somewhere in the init,
       and super.init called when there is a superclass — concept 25 *)
    (if init then
       match class_of with
       | Some cname ->
           let cl = Hashtbl.find classes cname in
           let inherited =
             match cl.Types.cl_super with
             | Some sup -> List.length (Hashtbl.find classes sup).Types.cl_fields
             | None -> 0
           in
           let own = List.filteri (fun i _ -> i >= inherited) cl.Types.cl_fields in
           List.iter
             (fun (fn, _) ->
               if not (Hashtbl.mem assigned_fields fn) then
                 err f.Ast.fspan "return from initializer without initializing all stored properties")
             own;
           if cl.Types.cl_super <> None && not !super_called then
             err f.Ast.fspan "'super.init' isn't called on all paths before returning from initializer"
       | None -> ());
    current_class := saved_class;
    in_init := saved_init;
    super_called := saved_super;
    current_throws := saved_throws;
    current_generics := saved_generics;
    if ret <> Types.TVoid && not (block_returns f.Ast.body) then
      err f.Ast.fspan
        (Printf.sprintf "missing return in function expected to return '%s'" (Types.string_of_ty ret))
  in

  (* CONFORMANCE CHECK (concept 21): for each `struct S : P`, P must be a declared protocol and
     S must implement every requirement with the exact signature. One error per failing
     protocol, at the struct — matching swiftc's "type 'S' does not conform to protocol 'P'". *)
  let check_conformances (s : Ast.struct_decl) : unit =
    List.iter
      (fun pname ->
        match Hashtbl.find_opt protos pname with
        | None ->
            if Hashtbl.mem structs pname || Hashtbl.mem enums pname || Types.of_name pname <> None then
              err s.Ast.sspan (Printf.sprintf "inheritance from non-protocol type '%s'" pname)
            else err s.Ast.sspan (Printf.sprintf "cannot find type '%s' in scope" pname)
        | Some _ ->
            if not (struct_conforms s.Ast.sname pname) then
              err s.Ast.sspan
                (Printf.sprintf "type '%s' does not conform to protocol '%s'" s.Ast.sname pname))
      s.Ast.sconforms
  in

  (* PASS 0: register struct and enum names (so declarations can reference each other), then
     fill the layouts. Now any type name resolves and the registries are known to passes 1–2. *)
  List.iter
    (function
      | Ast.IStruct s ->
          if Hashtbl.mem structs s.Ast.sname || Hashtbl.mem enums s.Ast.sname then
            err s.Ast.sspan (Printf.sprintf "invalid redeclaration of '%s'" s.Ast.sname);
          Hashtbl.replace structs s.Ast.sname { Types.sl_name = s.Ast.sname; sl_fields = [] }
      | Ast.IEnum e ->
          if Hashtbl.mem structs e.Ast.ename || Hashtbl.mem enums e.Ast.ename then
            err e.Ast.espan (Printf.sprintf "invalid redeclaration of '%s'" e.Ast.ename);
          if e.Ast.is_error then Hashtbl.replace error_enums e.Ast.ename ();
          Hashtbl.replace enums e.Ast.ename
            { Types.el_name = e.Ast.ename; el_cases = []; el_raw = e.Ast.eraw <> None }
      | Ast.IProto pr ->
          if Hashtbl.mem protos pr.Ast.pname || Hashtbl.mem structs pr.Ast.pname || Hashtbl.mem enums pr.Ast.pname
          then err pr.Ast.pspan (Printf.sprintf "invalid redeclaration of '%s'" pr.Ast.pname);
          Hashtbl.replace protos pr.Ast.pname { Types.pl_name = pr.Ast.pname; pl_reqs = [] }
      | Ast.IClass c ->
          if Hashtbl.mem classes c.Ast.cname || Hashtbl.mem structs c.Ast.cname then
            err c.Ast.cspan (Printf.sprintf "invalid redeclaration of '%s'" c.Ast.cname);
          Hashtbl.replace classes c.Ast.cname
            { Types.cl_name = c.Ast.cname; cl_super = c.Ast.csuper; cl_fields = []; cl_methods = []; cl_impls = [] }
      | _ -> ())
    prog.Ast.items;
  (* concept 25: build class layouts SUPERCLASS-FIRST (fields = super prefix + own; the vtable
     starts as the super's, an override replaces its slot, new methods append) *)
  let class_decls = List.filter_map (function Ast.IClass c -> Some c | _ -> None) prog.Ast.items in
  let built : (string, unit) Hashtbl.t = Hashtbl.create 8 in
  let rec build_layout (c : Ast.class_decl) : unit =
    if not (Hashtbl.mem built c.Ast.cname) then begin
      Hashtbl.replace built c.Ast.cname ();
      let super_layout =
        match c.Ast.csuper with
        | Some sup -> (
            match List.find_opt (fun (d : Ast.class_decl) -> d.Ast.cname = sup) class_decls with
            | Some sd -> build_layout sd; Hashtbl.find_opt classes sup
            | None ->
                err c.Ast.cspan (Printf.sprintf "cannot find type '%s' in scope" sup);
                None)
        | None -> None
      in
      let inherited_fields = match super_layout with Some sl -> sl.Types.cl_fields | None -> [] in
      let own_fields =
        List.map (fun (fl : Ast.field) -> (fl.Ast.fld_name, resolve_ty c.Ast.cspan fl.Ast.fld_ty)) c.Ast.cfields
      in
      let methods = ref (match super_layout with Some sl -> sl.Types.cl_methods | None -> []) in
      let impls = ref (match super_layout with Some sl -> sl.Types.cl_impls | None -> []) in
      List.iter
        (fun (is_override, (m : Ast.func_decl)) ->
          let ps = List.map (fun (p : Ast.param) -> resolve_silent p.Ast.ptype) m.Ast.params in
          let ret = match m.Ast.ret with None -> Types.TVoid | Some n -> resolve_silent n in
          let slot =
            let rec go i = function (n, _, _) :: _ when n = m.Ast.fname -> Some i | _ :: tl -> go (i + 1) tl | [] -> None in
            go 0 !methods
          in
          match (is_override, slot) with
          | true, Some i ->
              let _, sps, sret = List.nth !methods i in
              if sps <> ps || sret <> ret then
                err m.Ast.fspan
                  (Printf.sprintf "method does not override any method from its superclass");
              impls := List.mapi (fun j fn -> if j = i then c.Ast.cname ^ "." ^ m.Ast.fname else fn) !impls
          | true, None ->
              err m.Ast.fspan "method does not override any method from its superclass"
          | false, Some _ ->
              err m.Ast.fspan
                (Printf.sprintf "overriding declaration requires an 'override' keyword")
          | false, None ->
              methods := !methods @ [ (m.Ast.fname, ps, ret) ];
              impls := !impls @ [ c.Ast.cname ^ "." ^ m.Ast.fname ])
        c.Ast.cmethods;
      Hashtbl.replace classes c.Ast.cname
        { Types.cl_name = c.Ast.cname; cl_super = c.Ast.csuper; cl_fields = inherited_fields @ own_fields;
          cl_methods = !methods; cl_impls = !impls };
      (* the class must be constructible: a class that ADDS stored properties needs its own
         init; one that adds none INHERITS its superclass's (exactly Swift's rule) *)
      if c.Ast.cinit = None && own_fields <> [] then
        err c.Ast.cspan (Printf.sprintf "class '%s' has no initializers" c.Ast.cname)
    end
  in
  List.iter build_layout class_decls;
  (* v0 guard (concept 26): a class reference inside a VALUE type would be copied without a
     retain (structs/enums/optionals copy bitwise) — corrupting the refcount. Rejected until
     the copy machinery exists (the value-witness story, concept 23's exercise 4). *)
  let no_class_inside span what t =
    let rec has_class = function
      | Types.TClass _ -> true
      | Types.TOptional t -> has_class t
      | _ -> false
    in
    if has_class t then
      err span (Printf.sprintf "class references inside %s are not supported in this subset" what)
  in
  List.iter
    (function
      | Ast.IStruct s ->
          let fields =
            List.map (fun (fl : Ast.field) -> (fl.Ast.fld_name, resolve_ty s.Ast.sspan fl.Ast.fld_ty)) s.Ast.sfields
          in
          List.iter (fun (_, t) -> no_class_inside s.Ast.sspan "structs" t) fields;
          Hashtbl.replace structs s.Ast.sname { Types.sl_name = s.Ast.sname; sl_fields = fields }
      | Ast.IEnum e ->
          let cases =
            List.map
              (fun (c : Ast.enum_case) -> (c.Ast.cname, List.map (resolve_ty e.Ast.espan) c.Ast.payload))
              e.Ast.ecases
          in
          List.iter (fun (_, tys) -> List.iter (no_class_inside e.Ast.espan "enum payloads") tys) cases;
          Hashtbl.replace enums e.Ast.ename
            { Types.el_name = e.Ast.ename; el_cases = cases; el_raw = e.Ast.eraw <> None }
      | Ast.IProto pr ->
          (* requirement signatures, in declaration order (= witness-table slot order) *)
          let reqs =
            List.map
              (fun (r : Ast.proto_req) ->
                let ps = List.map (fun (p : Ast.param) -> resolve_ty pr.Ast.pspan p.Ast.ptype) r.Ast.rparams in
                let ret = match r.Ast.rret with None -> Types.TVoid | Some n -> resolve_ty pr.Ast.pspan n in
                (r.Ast.rname, ps, ret))
              pr.Ast.reqs
          in
          Hashtbl.replace protos pr.Ast.pname { Types.pl_name = pr.Ast.pname; pl_reqs = reqs }
      | _ -> ())
    prog.Ast.items;
  (* PASS 0.5 (concept 21): per-struct method signature tables — before any body is checked,
     so methods can call each other (and conformance can be decided). *)
  List.iter
    (function
      | Ast.IStruct st ->
          let sigs =
            List.map
              (fun (m : Ast.func_decl) ->
                let ps = List.map (fun (p : Ast.param) -> resolve_silent p.Ast.ptype) m.Ast.params in
                let ret = match m.Ast.ret with None -> Types.TVoid | Some n -> resolve_silent n in
                (m.Ast.fname, ps, ret))
              st.Ast.smethods
          in
          Hashtbl.replace methods st.Ast.sname sigs
      | _ -> ())
    prog.Ast.items;
  (* PASS 1: collect signatures so calls/recursion/forward-references resolve. *)
  List.iter
    (function
      | Ast.IClass c ->
          (* the init and each method register as functions C.init / C.m (self implicit) *)
          (match c.Ast.cinit with
          | Some init ->
              let ptys = List.map (fun (p : Ast.param) -> resolve_silent p.Ast.ptype) init.Ast.params in
              Hashtbl.replace funcs (c.Ast.cname ^ ".init") (ptys, Types.TVoid)
          | None -> ());
          List.iter
            (fun (_, (m : Ast.func_decl)) ->
              let ptys = List.map (fun (p : Ast.param) -> resolve_silent p.Ast.ptype) m.Ast.params in
              let ret = match m.Ast.ret with None -> Types.TVoid | Some n -> resolve_silent n in
              Hashtbl.replace funcs (c.Ast.cname ^ "." ^ m.Ast.fname) (ptys, ret))
            c.Ast.cmethods
      | Ast.IFunc f when f.Ast.generics <> [] ->
          if Hashtbl.mem funcs f.Ast.fname || Hashtbl.mem gfuncs f.Ast.fname then
            err f.Ast.fspan (Printf.sprintf "invalid redeclaration of '%s'" f.Ast.fname);
          let gs = List.filter_map (fun (n, c) -> Option.map (fun c -> (n, c)) c) f.Ast.generics in
          let saved = !current_generics in
          current_generics := gs @ !current_generics;
          let ptypes = List.map (fun (pr : Ast.param) -> resolve_silent pr.Ast.ptype) f.Ast.params in
          let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_silent n in
          current_generics := saved;
          if f.Ast.throws then Hashtbl.replace throwing f.Ast.fname ();
          Hashtbl.replace gfuncs f.Ast.fname (gs, ptypes, ret)
      | Ast.IFunc f ->
          if Hashtbl.mem funcs f.Ast.fname || Hashtbl.mem gfuncs f.Ast.fname then
            err f.Ast.fspan (Printf.sprintf "invalid redeclaration of '%s'" f.Ast.fname);
          let ptypes = List.map (fun (pr : Ast.param) -> resolve_silent pr.Ast.ptype) f.Ast.params in
          let ret = match f.Ast.ret with None -> Types.TVoid | Some n -> resolve_silent n in
          if f.Ast.throws then Hashtbl.replace throwing f.Ast.fname ();
          Hashtbl.replace funcs f.Ast.fname (ptypes, ret)
      | _ -> ())
    prog.Ast.items;
  (* PASS 2: conformance checks, then bodies (methods + functions) and top-level statements. *)
  List.iter (function Ast.IStruct st -> check_conformances st | _ -> ()) prog.Ast.items;
  List.iter
    (function
      | Ast.IFunc f -> check_func f
      | Ast.IStruct st -> List.iter (fun m -> check_func ~self_of:st.Ast.sname m) st.Ast.smethods
      | Ast.IClass c ->
          (match c.Ast.cinit with
          | Some init -> check_func ~class_of:c.Ast.cname ~init:true init
          | None -> ());
          (* the deinit body checks like a parameterless Void method (concept 26) *)
          (match c.Ast.cdeinit with
          | Some body ->
              check_func ~class_of:c.Ast.cname
                { Ast.fname = "deinit"; generics = []; params = []; throws = false; ret = None; body; fspan = c.Ast.cspan }
          | None -> ());
          List.iter (fun (_, m) -> check_func ~class_of:c.Ast.cname m) c.Ast.cmethods
      | Ast.IStmt s -> check_stmt s
      | Ast.IEnum _ | Ast.IProto _ -> ())
    prog.Ast.items
