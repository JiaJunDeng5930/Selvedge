(* Export existing kernel proof terms, not tactic reconstructions. Regeneration
   requires Rocq and MetaRocq; the normal Bend build checks the saved certificates. *)
From MetaRocq.Template Require Import All.
From Stdlib Require Import Lists.List.
Import MonadNotation.
Open Scope bs_scope.
Set Printing Width 1000000.

Definition quoted (s : string) := """" ++ s ++ """".
Definition array (xs : list string) := "[" ++ String.concat "," xs ++ "]".
Definition tag (s : string) (xs : list string) := array (quoted s :: xs).
Definition binder (a : aname) := match binder_name a with
  | nAnon => quoted "_" | nNamed s => quoted s end.

Fixpoint encode (fuel : nat) (t : term) : string :=
  match fuel with
  | O => tag "unsupported" [quoted "export fuel exhausted"]
  | S n =>
    let enc := encode n in
    match t with
    | tRel i => tag "rel" [string_of_nat i]
    | tSort s => tag "sort" [quoted (match s with sProp => "Prop" | sSProp => "SProp" | _ => "Type" end)]
    | tCast x _ ty => tag "cast" [enc x; enc ty]
    | tProd na ty b => tag "pi" [binder na; enc ty; enc b]
    | tLambda na ty b => tag "lam" [binder na; enc ty; enc b]
    | tLetIn na v ty b => tag "let" [binder na; enc v; enc ty; enc b]
    | tApp f args => tag "app" [enc f; array (map enc args)]
    | tConst kn _ => tag "const" [quoted (string_of_kername kn)]
    | tInd ind _ => tag "ind" [quoted (string_of_kername (inductive_mind ind)); string_of_nat (inductive_ind ind)]
    | tConstruct ind idx _ => tag "ctor" [quoted (string_of_kername (inductive_mind ind)); string_of_nat (inductive_ind ind); string_of_nat idx]
    | tCase _ p x branches => tag "case" [enc x; array (map binder (pcontext p)); enc (preturn p);
        array (map (fun b => array [array (map binder (bcontext b)); enc (bbody b)]) branches)]
    | tFix defs idx => tag "fix" [string_of_nat idx;
        array (map (fun d => array [binder (dname d); enc (dtype d); enc (dbody d); string_of_nat (rarg d)]) defs)]
    | _ => tag "unsupported" [quoted "term outside the certificate subset"]
    end
  end.

Definition export {A : Type} (value : A) : TemplateMonad unit :=
  q <- tmQuote value ;;
  match q with
  | tConst kn _ =>
    cb <- tmQuoteConstant kn true ;;
    match cst_body cb with
    | Some body =>
      out <- tmEval cbv ("SELVEDGE_PROOF:" ++ array
        [quoted (string_of_kername kn); encode 1024 (cst_type cb); encode 1024 body]) ;;
      tmPrint out
    | None => tmFail "A certificate must have a proof body"
    end
  | _ => tmFail "Export expects a named standard-library entity"
  end.

MetaRocq Run (export (@list_ind)).
MetaRocq Run (export (@List.app_nil_r)).
MetaRocq Run (export (@List.app_assoc)).
MetaRocq Run (export (@List.fold_left_app)).
MetaRocq Run (export (@List.map_app)).
MetaRocq Run (export (@List.map_map)).
MetaRocq Run (export (@List.map_id)).
Print Assumptions List.app_nil_r.
Print Assumptions List.app_assoc.
Print Assumptions List.fold_left_app.
Print Assumptions List.map_app.
Print Assumptions List.map_map.
Print Assumptions List.map_id.
